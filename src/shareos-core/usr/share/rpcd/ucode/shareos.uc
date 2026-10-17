// ShareOS rpcd plugin: ubus objects used by the web interface.
//
//   shareos.system   info | log | reboot | poweroff | factory_reset |
//                    set_password | set_hostname
//   shareos.service  list | action | autostart
//   shareos.net      get | set | confirm   (network with automatic rollback)
//   shareos.accounts list | add | set | passwd | del | group_add | group_del | import_altf
//   shareos.shares   list | set | del | global
//   shareos.me       bind | get | passwd   (the logged-in account, also for plain users)
//   shareos.backup   export | restore      (settings as JSON, optionally encrypted)
//   shareos.update   check | status | download | apply | cancel
//
// Long-running update steps run as a separate process (shareos-update) so
// rpcd's main loop is never blocked; the UI polls shareos.update.status.
'use strict';

import { readfile, writefile, popen, glob, stat, readlink, symlink, unlink } from 'fs';
import { cursor } from 'uci';

const UPDATER = '/usr/sbin/shareos-update';
const NET = '/usr/sbin/shareos-net';
const NET_ST = '/tmp/shareos-net';
const NET_ROLLBACK = '/etc/shareos/network.rollback';
const NET_TIMEOUT = 120;     // s until unconfirmed network settings are rolled back

// services the UI may show and control: init script -> process name
const SERVICES = {
	dropbear: { proc: 'dropbear', label: 'SSH / SFTP', desc: 'Dropbear, Port 22' },
	uhttpd:   { proc: 'uhttpd',   label: 'Weboberfläche', desc: 'uhttpd, Port 80' },
	ntpd:     { proc: 'ntpd',     label: 'Zeit (NTP)', desc: 'stellt die Uhr, gleicht die MCU-Uhr ab' },
	crond:    { proc: 'crond',    label: 'Zeitplaner', desc: 'cron' },
	rpcd:     { proc: 'rpcd',     label: 'API (rpcd)', desc: 'Schnittstelle für diese Oberfläche' },
	ubus:     { proc: 'ubusd',    label: 'Systembus (ubus)', desc: 'Nachrichten zwischen den Diensten' },
	syslogd:  { proc: 'syslogd',  label: 'Systemprotokoll', desc: 'syslogd, im RAM' },
	board:    { proc: 'dns320l-daemon', label: 'Gerätesteuerung', desc: 'Lüfter, Temperatur, Taster, MCU-Uhr' }
};
// services that must not be stopped from the UI (it would cut itself off)
const ESSENTIAL = { uhttpd: true, rpcd: true, ubus: true, board: true };

// services not started at boot (UCI shareos.autostart.disabled) as a set
function autostart_off() {
	let l = cursor().get('shareos', 'autostart', 'disabled') ?? [];
	if (type(l) != 'array') l = split(l, ' ');
	let o = {};
	for (let n in l) if (n != '') o[n] = true;
	return o;
}

function shq(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
}

function sh(cmd) {
	let p = popen(cmd + ' 2>&1', 'r');
	if (!p)
		return { rc: -1, out: '' };
	let out = p.read('all') ?? '';
	let rc = p.close();
	return { rc, out };
}

function read_trim(path) {
	let d = readfile(path);
	return d != null ? trim(replace(d, '\0', '')) : null;
}

function read_int(path) {
	let v = read_trim(path);
	return v != null && match(v, /^-?[0-9]+$/) ? +v : null;
}

function release() {
	let r = {};
	for (let line in split(readfile('/etc/shareos-release') ?? '', '\n')) {
		let m = match(line, /^([A-Z_]+)="?([^"]*)"?$/);
		if (m) r[lc(replace(m[1], 'SHAREOS_', ''))] = m[2];
	}
	return r;
}

function meminfo() {
	let m = {};
	for (let line in split(readfile('/proc/meminfo') ?? '', '\n')) {
		let x = match(line, /^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree):\s+([0-9]+) kB/);
		if (x) m[lc(x[1])] = +x[2] * 1024;
	}
	return m;
}

// jiffies of the first "cpu" line; the UI computes the load from two samples
function cpustat() {
	let l = match(readfile('/proc/stat') ?? '', /^cpu +([0-9 ]+)/);
	if (!l)
		return null;
	let v = map(split(trim(l[1]), / +/), (x) => +x);
	let idle = v[3] + (v[4] ?? 0);
	let total = 0;
	for (let x in v) total += x;
	return { total, idle };
}

function disks() {
	let list = [];
	for (let d in glob('/sys/block/sd*')) {
		let name = substr(d, 11);
		push(list, {
			name,
			model: read_trim(d + '/device/model'),
			size: (read_int(d + '/size') ?? 0) * 512,
			removable: read_int(d + '/removable') == 1
		});
	}
	return list;
}

// df for the mount points the UI shows
function filesystems() {
	let list = [];
	let r = sh('df -k /overlay /rom /tmp');
	for (let line in split(r.out, '\n')) {
		let f = split(trim(line), /\s+/);
		if (length(f) >= 6 && match(f[1], /^[0-9]+$/))
			push(list, { source: f[0], mount: f[5], size: +f[1] * 1024, used: +f[2] * 1024, avail: +f[3] * 1024 });
	}
	return list;
}

function ipv4(ifname) {
	let r = sh('ip -4 -o addr show dev ' + shq(ifname));
	let m = match(r.out, /inet ([0-9.]+)\/([0-9]+)/);
	return m ? { address: m[1], prefix: +m[2] } : null;
}

function gateway() {
	let m = match(sh('ip -4 route show default').out, /default via ([0-9.]+)/);
	return m?.[1];
}

function dns() {
	let list = [];
	for (let line in split(readfile('/etc/resolv.conf') ?? '', '\n')) {
		let m = match(line, /^nameserver\s+(\S+)/);
		if (m) push(list, m[1]);
	}
	return list;
}

function boot_mode() {
	let mounts = readfile('/proc/mounts') ?? '';
	if (match(mounts, / \/overlay ubifs /)) return 'flash';
	if (match(readfile('/proc/cmdline') ?? '', /shareos\.netroot=/)) return 'netroot';
	return 'ram';
}

function run_updater(args) {
	let p = popen(join(' ', [ UPDATER, ...map(args, shq) ]) + ' 2>/dev/null', 'r');
	let out = p ? (p.read('all') ?? '') : '';
	p?.close();
	let res = null;
	try { res = json(out); } catch (e) { }
	return type(res) == 'object' ? res : { state: 'error', error: 'updater returned no result' };
}

function spawn_updater(args) {
	// detached, so the ubus call returns at once
	system(sprintf('start-stop-daemon -S -b -x %s -- %s', UPDATER, join(' ', map(args, shq))));
	return { started: true };
}

function running(proc) {
	return sh('pidof ' + shq(proc)).rc == 0;
}

function init_script(name) {
	let s = glob('/etc/init.d/S[0-9][0-9]' + name);
	return length(s) == 1 ? s[0] : null;
}


/* ---------- storage ---------- */

const STORAGE = '/usr/sbin/shareos-storage';
const SMART_DIR = '/tmp/shareos-storage';
const SMART_MAX_AGE = 1800;     // s; SMART reads keep disks awake, so cache them

function valid_name(n) { return type(n) == 'string' && match(n, /^[a-z0-9][a-z0-9_-]{0,15}$/); }
function valid_disk(d) { return type(d) == 'string' && match(d, /^sd[a-z]$/) && stat('/sys/block/' + d); }

function ubiblock_major() {
	let m = match(readfile('/proc/devices') ?? '', /\n *([0-9]+) ubiblock\n/);
	return m ? m[1] : null;
}

function lsblk() {
	// -e: leave out mtdblock (31), ram (1) and ubiblock devices – only disks matter here
	let r = sh('lsblk -J -b -e 1,31,' + (ubiblock_major() ?? '31') + ' -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL,SERIAL,TRAN,RM,ROTA');
	let j = null;
	try { j = json(r.out); } catch (e) { }
	return j?.blockdevices ?? [];
}

function smart_read(disk, refresh) {
	let cache = SMART_DIR + '/smart-' + disk + '.json';
	let st = stat(cache);
	if (!refresh && st && time() - st.mtime < SMART_MAX_AGE) {
		let c = null;
		try { c = json(readfile(cache)); } catch (e) { }
		if (c) return c;
	}
	if (!refresh && !st)
		return null;
	// -n standby: do not wake a sleeping disk just for SMART
	let r = sh('smartctl -j -n standby -H -A -i /dev/' + disk);
	let j = null;
	try { j = json(r.out); } catch (e) { }
	if (!j)
		return { error: 'no SMART data' };
	if (j.smartctl?.exit_status == 2 && match(r.out, /standby|STANDBY|sleep/))
		return { standby: true };
	let attr = {};
	for (let a in j.ata_smart_attributes?.table ?? [])
		attr[a.id] = a.raw?.value;
	let res = {
		time: time(),
		passed: j.smart_status?.passed,
		temperature: j.temperature?.current,
		power_on_hours: j.power_on_time?.hours,
		power_cycles: j.power_cycle_count,
		reallocated: attr[5],
		pending: attr[197],
		uncorrectable: attr[198],
		model: j.model_name,
		serial: j.serial_number,
		firmware: j.firmware_version,
		rpm: j.rotation_rate
	};
	system('mkdir -p ' + SMART_DIR);
	writefile(cache, sprintf('%J', res));
	return res;
}

function mdstat() {
	let arrays = {};
	let cur = null;
	for (let line in split(readfile('/proc/mdstat') ?? '', '\n')) {
		let m = match(line, /^(md[0-9]+) : (\S+) (\S+) (.*)$/);
		if (m) {
			cur = { name: m[1], state: m[2], level: m[3], members: map(split(trim(m[4]), ' '), (x) => replace(x, /\[[0-9]+\](\(.\))?/, '')) };
			arrays[m[1]] = cur;
			continue;
		}
		if (!cur) continue;
		let h = match(line, /\[([0-9]+)\/([0-9]+)\] \[([U_]+)\]/);
		if (h) { cur.disks = +h[1]; cur.active = +h[2]; cur.health = h[3]; }
		let p = match(line, /(resync|recovery|check|reshape) *= *([0-9.]+)%.*finish=([0-9.]+min)/);
		if (p) { cur.sync = { action: p[1], percent: +p[2], finish: p[3] }; }
		let d = match(line, /(resync|recovery)=DELAYED/);
		if (d) cur.sync = { action: d[1], percent: 0, delayed: true };
	}
	return arrays;
}

function storage_job() {
	let j = {};
	for (let line in split(readfile(SMART_DIR + '/job') ?? '', '\n')) {
		let m = match(line, /^([a-z]+)=(.*)$/);
		if (m) j[m[1]] = m[2];
	}
	if (j.state == 'running' && !stat(SMART_DIR + '/lock')) {
		j.state = 'error';
		j.error = j.error ?? 'job ended unexpectedly';
	}
	return length(j) ? j : null;
}

function volumes() {
	let list = [];
	let c = cursor();
	let mounts = readfile('/proc/mounts') ?? '';
	c.foreach('storage', 'volume', function(s) {
		let name = s['.name'];
		let dev = s.uuid ? trim(sh('blkid -o device -t UUID=' + shq(s.uuid) + ' /dev/sd[a-z]* /dev/md[0-9]* /dev/loop[0-9]* 2>/dev/null | head -1').out) : null;
		let mp = '/mnt/' + name;
		let mounted = index(mounts, ' ' + mp + ' ') >= 0;
		let v = { name, uuid: s.uuid, fstype: s.fstype, layout: s.layout, enabled: s.enabled != '0',
			device: dev && length(dev) ? dev : null, mountpoint: mp, mounted };
		if (mounted) {
			let f = split(trim(split(sh('df -k ' + shq(mp)).out, '\n')[1] ?? ''), /\s+/);
			if (length(f) >= 4) { v.size = +f[1] * 1024; v.used = +f[2] * 1024; v.avail = +f[3] * 1024; }
		}
		push(list, v);
	});
	return list;
}

function spawn_storage(args) {
	system(sprintf('start-stop-daemon -S -b -x %s -- %s', STORAGE, join(' ', map(args, shq))));
	return { started: true };
}

/* ---------- web interface: language, logo, HTTPS ---------- */

const CERT = '/usr/sbin/shareos-cert';

const THEMES = { dark: 1, light: 1, system: 1 };
const ACCENTS = { blue: 1, green: 1, red: 1, white: 1 };

function ui_settings() {
	let c = cursor();
	let theme = c.get('shareos', 'ui', 'theme'), accent = c.get('shareos', 'ui', 'accent');
	return {
		lang: c.get('shareos', 'ui', 'lang') ?? 'en',
		logo: (c.get('shareos', 'ui', 'logo') ?? '1') != '0',
		theme: THEMES[theme] ? theme : 'dark',
		accent: ACCENTS[accent] ? accent : 'blue'
	};
}

/* ---------- network ---------- */

function ip4_ok(a) {
	let m = match(a ?? '', /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/);
	if (!m) return false;
	for (let i = 1; i <= 4; i++) if (+m[i] > 255) return false;
	return true;
}

function pow2(n) {
	let v = 1;
	for (let i = 0; i < n; i++) v *= 2;
	return v;
}

function ip4_num(a) {
	let p = split(a, '.');
	return ((+p[0] * 256 + +p[1]) * 256 + +p[2]) * 256 + +p[3];
}

// prefix length of a netmask, null if the mask is not contiguous
function mask_prefix(m) {
	if (!ip4_ok(m)) return null;
	let n = ip4_num(m), bits = 0;
	for (let i = 31; i >= 0; i--) {
		let b = int(n / (pow2(i))) % 2;
		if (b == 1 && bits == 31 - i) bits++;
		else if (b == 1) return null;
	}
	return bits;
}

function net_settings() {
	let c = cursor();
	let dns = c.get('network', 'lan', 'dns') ?? '';
	if (type(dns) == 'array') dns = join(' ', dns);
	return {
		proto: c.get('network', 'lan', 'proto') == 'static' ? 'static' : 'dhcp',
		ipaddr: c.get('network', 'lan', 'ipaddr') ?? '',
		netmask: c.get('network', 'lan', 'netmask') ?? '255.255.255.0',
		gateway: c.get('network', 'lan', 'gateway') ?? '',
		dns: filter(split(trim(dns), /[ ,]+/), (x) => x != '')
	};
}

function net_state() {
	let pending = read_int(NET_ST + '/pending');
	return {
		pending: pending != null ? { until: pending, left: (pending > time() ? pending - time() : 0) } : null,
		result: read_trim(NET_ST + '/result')
	};
}

function cert_info() {
	let r = sh(CERT + ' info');
	let i = { san: [] };
	for (let line in split(r.out, '\n')) {
		let m = match(line, /^([a-z]+)=(.*)$/);
		if (!m) continue;
		if (m[1] == 'san') push(i.san, m[2]);
		else i[m[1]] = m[2];
	}
	i.selfsigned = !!(i.issuer && i.issuer == i.subject);
	return i;
}

// uhttpd runs under shareos-uhttpd, which reads the settings again on restart
function restart_uhttpd() {
	system('(sleep 1; killall uhttpd) >/dev/null 2>&1 &');
}

/* ---------- hardware settings, first run, Alt-F ---------- */

const FAN_PRESETS = {
	quiet:    { off_temp: 40, full_temp: 55, half_temp: 50 },
	balanced: { off_temp: 0,  full_temp: 50, half_temp: 45 },
	cool:     { off_temp: 0,  full_temp: 45, half_temp: 42 }
};

function fan_settings() {
	let c = cursor();
	let preset = c.get('shareos', 'fan', 'preset') ?? 'balanced';
	let v = FAN_PRESETS[preset] ?? {
		off_temp: +(c.get('shareos', 'fan', 'off_temp') ?? 0),
		full_temp: +(c.get('shareos', 'fan', 'full_temp') ?? 50),
		half_temp: +(c.get('shareos', 'fan', 'half_temp') ?? 45)
	};
	return { preset, ...v };
}

function led_settings() {
	let c = cursor();
	return {
		status: c.get('shareos', 'led', 'status') ?? 'heartbeat',
		power: c.get('shareos', 'led', 'power') ?? 'on',
		disks: c.get('shareos', 'led', 'disks') ?? 'off'
	};
}

function timezone() {
	let t = trim(readfile('/etc/timezone') ?? '');
	if (t != '') return t;
	let l = readlink('/etc/localtime');
	return l ? replace(l, /^.*zoneinfo\//, '') : 'UTC';
}

function zones() {
	let list = [];
	for (let line in split(readfile('/usr/share/zoneinfo/zone1970.tab') ?? readfile('/usr/share/zoneinfo/zone.tab') ?? '', '\n')) {
		if (substr(line, 0, 1) == '#') continue;
		let f = split(line, '\t');
		if (length(f) >= 3) push(list, f[2]);
	}
	if (!length(list))
		for (let d in [ 'Africa', 'America', 'Asia', 'Atlantic', 'Australia', 'Europe', 'Pacific' ])
			for (let z in glob('/usr/share/zoneinfo/' + d + '/*'))
				push(list, substr(z, 20));
	push(list, 'UTC');
	return sort(uniq(list));
}

function set_timezone(tz) {
	if (!match(tz ?? '', /^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+)*$/) || !stat('/usr/share/zoneinfo/' + tz))
		return false;
	unlink('/etc/localtime');
	symlink('/usr/share/zoneinfo/' + tz, '/etc/localtime');
	writefile('/etc/timezone', tz + '\n');
	return true;
}

function altf_scan() {
	let r = sh('/usr/sbin/shareos-altf scan');
	let a = { users: [], shares: [], nfs: [] };
	for (let line in split(r.out, '\n')) {
		let m = match(line, /^([a-z_]+)=(.*)$/);
		if (!m) continue;
		if (m[1] == 'user') push(a.users, m[2]);
		else if (m[1] == 'share') push(a.shares, m[2]);
		else if (m[1] == 'nfs') push(a.nfs, m[2]);
		else a[m[1]] = m[2];
	}
	a.found = a.found == '1';
	return a;
}

function set_password(pw) {
	if (length(pw ?? '') < 6) return 'password too short (min. 6)';
	if (match(pw, /[\n\r:]/)) return 'password contains invalid characters';
	let p = popen('chpasswd -c sha512 >/dev/null 2>&1', 'w');
	if (!p) return 'chpasswd not available';
	p.write('root:' + pw + '\n');
	return p.close() == 0 ? null : 'chpasswd failed';
}

function set_hostname(h) {
	if (!match(h ?? '', /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/)) return false;
	writefile('/etc/hostname', h + '\n');
	sh('hostname ' + shq(h));
	return true;
}


/* ---------- accounts, shares, the logged-in user ---------- */

const USERS = '/usr/sbin/shareos-users';
const SHARES = '/usr/sbin/shareos-shares';
const QUOTA = '/usr/sbin/shareos-quota';
const SESS_DIR = '/tmp/shareos-sessions';
const ACC_RE = /^[a-z][a-z0-9_]{0,31}$/;

function acc_name_ok(n) { return type(n) == 'string' && match(n, ACC_RE); }

// run a tool with the password on stdin (never on the command line)
function sh_pass(cmd, pass) {
	return sh(sprintf("printf '%%s\\n' %s | %s", shq(pass ?? ''), cmd));
}
function tool_result(r) {
	if (r.rc == 0) return { ok: true, output: trim(r.out) };
	let m = match(r.out, /error: ([^\n]*)/);
	return { error: m ? m[1] : (trim(r.out) || 'failed') };
}

function opt_args(a) {
	let o = [];
	if (a.fullname != null) push(o, '--fullname=' + a.fullname);
	if (a.groups != null) push(o, '--groups=' + join(',', a.groups));
	if (a.home != null) push(o, '--home=' + a.home);
	if (a.quota != null) push(o, '--quota=' + int(+a.quota));
	if (a.web != null) push(o, '--web=' + (a.web ? '1' : '0'));
	if (a.role != null) push(o, '--role=' + a.role);
	return join(' ', map(o, shq));
}

function quota_usage() {   // user -> [{volume, used, limit}] in bytes
	let u = {};
	for (let line in split(sh(QUOTA + ' report').out, '\n')) {
		let m = match(line, /^user=([^:]+):([^:]+):([0-9]+):([0-9]+)$/);
		if (!m) continue;
		u[m[1]] ??= [];
		push(u[m[1]], { volume: m[2], used: +m[3] * 1024, limit: +m[4] * 1024 });
	}
	return u;
}

function list_of(v) { return v == null ? [] : (type(v) == 'array' ? v : split(v, ' ')); }

function accounts() {
	let c = cursor(), users = [], groups = [];
	let usage = quota_usage();
	c.foreach('accounts', 'user', (x) => {
		push(users, {
			name: x['.name'], role: x.role ?? 'share', fullname: x.fullname ?? '', uid: +(x.uid ?? 0),
			groups: list_of(x.groups), home: x.home ?? '', quota: +(x.quota ?? 0), web: (x.web ?? '1') != '0',
			usage: usage[x['.name']] ?? []
		});
	});
	c.foreach('accounts', 'group', (x) => {
		push(groups, { name: x['.name'], desc: x.desc ?? '',
			members: map(filter(users, (u) => index(u.groups, x['.name']) >= 0), (u) => u.name) });
	});
	return { users: sort(users, (a, b) => a.name < b.name ? -1 : 1), groups: sort(groups, (a, b) => a.name < b.name ? -1 : 1) };
}

function share_list() {
	let c = cursor(), list = [];
	let st = {};
	for (let line in split(sh(SHARES + ' status').out, '\n')) {
		let m = match(line, /^share=([^:]*):([^:]*):([01])$/);
		if (m) st[m[1]] = { path: m[2], mounted: m[3] == '1' };
	}
	c.foreach('shares', 'share', (x) => {
		let n = x['.name'];
		push(list, {
			name: n, volume: x.volume ?? '', path: x.path ?? n, comment: x.comment ?? '',
			smb: x.smb == '1', nfs: x.nfs == '1', guest: x.guest == '1',
			rw: list_of(x.rw), ro: list_of(x.ro), nfs_rw: x.nfs_rw == '1', nfs_hosts: list_of(x.nfs_hosts),
			fullpath: st[n]?.path ?? null, mounted: st[n]?.mounted ?? false
		});
	});
	let svc = sh(SHARES + ' status').out;
	return {
		shares: sort(list, (a, b) => a.name < b.name ? -1 : 1),
		workgroup: c.get('shares', 'global', 'workgroup') ?? 'WORKGROUP',
		smb_enabled: (c.get('shares', 'global', 'smb') ?? '1') != '0',
		nfs_enabled: (c.get('shares', 'global', 'nfs') ?? '1') != '0',
		smb_running: !!match(svc, /smb=1/), nfs_running: !!match(svc, /nfs=1/)
	};
}

// which account belongs to a web session: set by "bind" right after login
function session_user(req) {
	let sid = req.args?.ubus_rpc_session;
	if (type(sid) != 'string' || !match(sid, /^[0-9a-f]{32}$/)) return null;
	let u = read_trim(SESS_DIR + '/' + sid);
	return u && (u == 'root' || acc_name_ok(u)) ? u : null;
}

// check a password against /etc/shadow (crypt via busybox mkpasswd)
function password_ok(user, pass) {
	let line = filter(split(readfile('/etc/shadow') ?? '', '\n'), (l) => index(l, user + ':') == 0)[0];
	let hash = line ? split(line, ':')[1] : null;
	if (!hash || length(hash) < 13 || substr(hash, 0, 1) == '!' || substr(hash, 0, 1) == '*') return false;
	let m = match(hash, /^\$([156])\$([^$]+)\$/);
	let method = m ? { '1': 'md5', '5': 'sha256', '6': 'sha512' }[m[1]] : 'des';
	let salt = m ? m[2] : substr(hash, 0, 2);
	let r = sh(sprintf("printf '%%s' %s | mkpasswd -P 0 -m %s -S %s", shq(pass), method, shq(salt)));
	return trim(r.out) == hash;
}

function me_info(u) {
	let c = cursor();
	let role = u == 'root' ? 'admin' : (c.get('accounts', u, 'role') ?? 'share');
	let info = { name: u, role, fullname: u == 'root' ? 'Administrator' : (c.get('accounts', u, 'fullname') ?? ''),
		groups: list_of(c.get('accounts', u, 'groups')), quota: +(c.get('accounts', u, 'quota') ?? 0) };
	let home = c.get('accounts', u, 'home');
	info.home = home ? { volume: home, path: '/mnt/' + home + '/home/' + u, smb: u } : null;
	info.usage = quota_usage()[u] ?? [];
	// shares this account can reach and how
	let mine = [];
	let tags = [ u, ...map(info.groups, (g) => '@' + g) ];
	c.foreach('shares', 'share', (x) => {
		let rw = list_of(x.rw), ro = list_of(x.ro), access = null;
		for (let t in tags) { if (index(rw, t) >= 0) access = 'rw'; else if (!access && index(ro, t) >= 0) access = 'ro'; }
		if (!access && x.guest == '1') access = 'ro';
		if (access && x.smb == '1') push(mine, { name: x['.name'], access, comment: x.comment ?? '' });
	});
	info.shares = mine;
	info.host = read_trim('/proc/sys/kernel/hostname');
	return info;
}

/* ---------- settings backup ---------- */

const CRYPT = '/usr/sbin/shareos-crypt';
const BACKUP_CONFIGS = [ 'shareos', 'storage', 'network', 'accounts', 'shares' ];
const BACKUP_FILES = [ '/etc/ksmbd/ksmbdpwd.db', '/etc/ssl/shareos/server.crt', '/etc/ssl/shareos/server.key', '/etc/hostname', '/etc/timezone' ];

function lines_of(path) { return filter(split(readfile(path) ?? '', '\n'), (l) => l != ''); }
function field(l, i) { return split(l, ':')[i]; }

// run shareos-crypt: the password is the first line of its input
function crypt(mode, pass, data) {
	let tin = '/tmp/.sos-crypt-in', tout = '/tmp/.sos-crypt-out';
	system('umask 077; : > ' + tin);
	writefile(tin, pass + '\n' + data);
	let r = sh(sprintf('%s %s < %s > %s', CRYPT, mode, tin, tout));
	let out = readfile(tout);
	unlink(tin); unlink(tout);
	return r.rc == 0 ? { data: out } : { error: r.rc == 2 ? 'wrong password or damaged file' : 'encryption failed' };
}

function backup_build() {
	let b = { shareos_backup: 1, version: release().version, host: read_trim('/proc/sys/kernel/hostname'),
		created: time(), configs: {}, files: {}, accounts: {} };
	for (let c in BACKUP_CONFIGS) {
		let t = readfile('/etc/config/' + c);
		if (t != null) b.configs[c] = t;
	}
	for (let f in BACKUP_FILES) {
		let t = readfile(f);
		if (t != null) b.files[f] = t;
	}
	let tz = readlink('/etc/localtime');
	if (tz) b.files['/etc/localtime'] = { link: tz };
	// accounts: uid/gid >= 1000 plus the root password
	b.accounts.passwd = filter(lines_of('/etc/passwd'), (l) => +field(l, 2) >= 1000 && +field(l, 2) < 65534);
	let names = map(b.accounts.passwd, (l) => field(l, 0));
	b.accounts.shadow = filter(lines_of('/etc/shadow'), (l) => field(l, 0) == 'root' || index(names, field(l, 0)) >= 0);
	b.accounts.group = filter(lines_of('/etc/group'), (l) => +field(l, 2) >= 1000 && +field(l, 2) < 65534);
	return b;
}

function backup_summary(b) {
	let users = map(b.accounts?.passwd ?? [], (l) => field(l, 0));
	let shares = [];
	for (let l in split(b.configs?.shares ?? '', '\n')) {
		let m = match(l, /^config share '([^']+)'/);
		if (m) push(shares, m[1]);
	}
	return { version: b.version, host: b.host, created: b.created, users, shares,
		configs: keys(b.configs ?? {}), certificate: !!b.files?.['/etc/ssl/shareos/server.key'] };
}

function backup_restore(b) {
	let ACC = /^[a-z][a-z0-9_]{0,31}$/;
	for (let c in keys(b.configs ?? {})) {
		if (index(BACKUP_CONFIGS, c) < 0 || type(b.configs[c]) != 'string') continue;
		writefile('/etc/config/' + c, b.configs[c]);
	}
	for (let f in keys(b.files ?? {})) {
		let v = b.files[f];
		if (f == '/etc/localtime') {
			if (type(v) == 'object' && match(v.link ?? '', /^\/usr\/share\/zoneinfo\/[A-Za-z0-9_+\/-]+$/) && stat(v.link)) {
				unlink('/etc/localtime'); symlink(v.link, '/etc/localtime');
			}
			continue;
		}
		if (index(BACKUP_FILES, f) < 0 || type(v) != 'string') continue;
		system('mkdir -p ' + shq(replace(f, /\/[^\/]+$/, '')));
		writefile(f, v);
		if (match(f, /\.key$|ksmbdpwd/)) system('chmod 600 ' + shq(f));
	}
	if (b.files?.['/etc/hostname']) system('hostname ' + shq(trim(b.files['/etc/hostname'])));
	// accounts: replace everything with uid/gid >= 1000, keep system accounts
	let good = (l, n) => length(split(l, ':')) == n && match(field(l, 0), ACC);
	let pw = filter(b.accounts?.passwd ?? [], (l) => good(l, 7) && +field(l, 2) >= 1000);
	let names = map(pw, (l) => field(l, 0));
	let sh_new = filter(b.accounts?.shadow ?? [], (l) => length(split(l, ':')) >= 2 && (field(l, 0) == 'root' || index(names, field(l, 0)) >= 0));
	let grp = filter(b.accounts?.group ?? [], (l) => good(l, 4) && +field(l, 2) >= 1000);
	let keep = (path, test) => filter(lines_of(path), test);
	let passwd = [ ...keep('/etc/passwd', (l) => !(+field(l, 2) >= 1000 && +field(l, 2) < 65534)), ...pw ];
	let rootsh = filter(sh_new, (l) => field(l, 0) == 'root')[0];
	// system accounts keep their shadow line (root gets the backed-up password),
	// accounts from the backup bring theirs; all others are gone
	let sysnames = map(passwd, (l) => field(l, 0));
	let shadow = [ ...map(filter(lines_of('/etc/shadow'), (l) => index(sysnames, field(l, 0)) >= 0 && index(names, field(l, 0)) < 0),
			(l) => field(l, 0) == 'root' && rootsh ? rootsh : l),
		...filter(sh_new, (l) => field(l, 0) != 'root') ];
	let group = [ ...keep('/etc/group', (l) => !(+field(l, 2) >= 1000 && +field(l, 2) < 65534)), ...grp ];
	writefile('/etc/passwd', join('\n', passwd) + '\n');
	writefile('/etc/shadow', join('\n', shadow) + '\n');
	system('chmod 600 /etc/shadow');
	writefile('/etc/group', join('\n', group) + '\n');
	system(USERS + ' sync >/dev/null 2>&1');
	return { ok: true, reboot: true };
}

return {
	'shareos.ui': {
		// public (also before login): language and logo for the login page
		get: {
			call: function() { return ui_settings(); }
		},

		set: {
			args: { lang: '', logo: false, theme: '', accent: '' },
			call: function(req) {
				let c = cursor();
				c.set('shareos', 'ui', 'ui');   // section may be missing in configs from older versions
				if (req.args.lang != null && req.args.lang != '') {
					if (!match(req.args.lang, /^[a-z]{2}(-[A-Za-z]{2})?$/)) return { error: 'invalid language' };
					c.set('shareos', 'ui', 'lang', req.args.lang);
				}
				if (req.args.logo != null)
					c.set('shareos', 'ui', 'logo', req.args.logo ? '1' : '0');
				if (req.args.theme) {
					if (!THEMES[req.args.theme]) return { error: 'invalid theme' };
					c.set('shareos', 'ui', 'theme', req.args.theme);
				}
				if (req.args.accent) {
					if (!ACCENTS[req.args.accent]) return { error: 'invalid accent' };
					c.set('shareos', 'ui', 'accent', req.args.accent);
				}
				c.commit('shareos');
				return ui_settings();
			}
		}
	},

	'shareos.web': {
		get: {
			call: function() {
				let c = cursor();
				return { https: c.get('shareos', 'web', 'https') != '0', redirect: c.get('shareos', 'web', 'redirect') == '1', cert: cert_info() };
			}
		},

		set: {
			args: { https: true, redirect: false },
			call: function(req) {
				let c = cursor();
				c.set('shareos', 'web', 'web');
				if (req.args.https != null) c.set('shareos', 'web', 'https', req.args.https ? '1' : '0');
				if (req.args.redirect != null) c.set('shareos', 'web', 'redirect', req.args.redirect ? '1' : '0');
				c.commit('shareos');
				restart_uhttpd();
				return { ok: true };
			}
		},

		selfsigned: {
			call: function() {
				let r = sh(CERT + ' selfsigned');
				if (r.rc != 0) return { error: trim(r.out) };
				restart_uhttpd();
				return { ok: true, cert: cert_info() };
			}
		},

		install: {
			// PEM texts; the certificate may be followed by the chain
			args: { cert: '', key: '' },
			call: function(req) {
				let crt = req.args.cert ?? '', key = req.args.key ?? '';
				if (length(crt) > 65536 || length(key) > 16384) return { error: 'file too large' };
				let d = trim(sh('mktemp -d').out);
				writefile(d + '/crt', crt);
				writefile(d + '/key', key);
				let r = sh(CERT + ' install ' + shq(d + '/crt') + ' ' + shq(d + '/key'));
				system('rm -rf ' + shq(d));
				if (r.rc != 0) return { error: replace(trim(r.out), 'shareos-cert: ', '') };
				restart_uhttpd();
				return { ok: true, cert: cert_info() };
			}
		}
	},

	'shareos.system': {
		info: {
			call: function() {
				let up = split(read_trim('/proc/uptime') ?? '0', ' ');
				let load = split(read_trim('/proc/loadavg') ?? '', ' ');
				let net = '/sys/class/net/eth0/';
				return {
					model: read_trim('/proc/device-tree/model'),
					release: release(),
					hostname: read_trim('/proc/sys/kernel/hostname'),
					kernel: read_trim('/proc/sys/kernel/osrelease'),
					boot: boot_mode(),
					time: time(),
					uptime: +up[0],
					load: [ +load[0], +load[1], +load[2] ],
					cpu: cpustat(),
					memory: meminfo(),
					temperature: read_int('/tmp/sys/temp1_input'),   // m°C, from dns320l-daemon
					fan_pwm: read_int('/tmp/sys/pwm1'),
					network: {
						eth0: {
							ipv4: ipv4('eth0'),
							gateway: gateway(),
							dns: dns(),
							speed: read_int(net + 'speed'),
							mac: read_trim(net + 'address'),
							rx_bytes: read_int(net + 'statistics/rx_bytes'),
							tx_bytes: read_int(net + 'statistics/tx_bytes')
						}
					},
					filesystems: filesystems(),
					disks: disks()
				};
			}
		},

		log: {
			args: { lines: 200, source: 'system' },
			call: function(req) {
				let n = +(req.args.lines ?? 200);
				if (n < 1 || n > 2000) n = 200;
				let r = req.args.source == 'kernel'
					? sh('dmesg | tail -n ' + n)
					: sh('tail -n ' + n + ' /var/log/messages');
				return { lines: split(rtrim(r.out), '\n') };
			}
		},

		reboot: {
			call: function() {
				system('(sleep 2; reboot) >/dev/null 2>&1 &');
				return { rebooting: true };
			}
		},

		poweroff: {
			args: { confirm: false },
			call: function(req) {
				if (req.args.confirm !== true)
					return { error: 'confirm must be true' };
				system('(sleep 2; poweroff) >/dev/null 2>&1 &');
				return { poweroff: true };
			}
		},

		factory_reset: {
			args: { confirm: false },
			call: function(req) {
				if (req.args.confirm !== true)
					return { error: 'confirm must be true' };
				let r = sh('/usr/sbin/shareos-factory-reset --yes --no-reboot');
				if (r.rc != 0)
					return { error: trim(r.out) };
				system('(sleep 2; reboot) >/dev/null 2>&1 &');
				return { rebooting: true };
			}
		},

		set_password: {
			args: { password: '' },
			call: function(req) {
				let pw = req.args.password ?? '';
				if (length(pw) < 6)
					return { error: 'password too short (min. 6)' };
				if (match(pw, /[\n\r:]/))
					return { error: 'password contains invalid characters' };
				let p = popen('chpasswd -c sha512 >/dev/null 2>&1', 'w');
				if (!p)
					return { error: 'chpasswd not available' };
				p.write('root:' + pw + '\n');
				return p.close() == 0 ? { ok: true } : { error: 'chpasswd failed' };
			}
		},

		set_hostname: {
			args: { hostname: '' },
			call: function(req) {
				let h = req.args.hostname ?? '';
				if (!match(h, /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/))
					return { error: 'invalid hostname' };
				writefile('/etc/hostname', h + '\n');
				sh('hostname ' + shq(h));
				return { ok: true, hostname: h };
			}
		}
	},

	'shareos.service': {
		list: {
			call: function() {
				let list = [];
				for (let name in sort(keys(SERVICES))) {
					let s = SERVICES[name];
					if (!init_script(name))
						continue;
					push(list, { name, label: s.label, desc: s.desc, running: running(s.proc), essential: !!ESSENTIAL[name],
						autostart: !(name in autostart_off()) });
				}
				return { services: list };
			}
		},

		action: {
			args: { name: '', action: '' },
			call: function(req) {
				let name = req.args.name, act = req.args.action;
				let script = SERVICES[name] ? init_script(name) : null;
				if (!script)
					return { error: 'unknown service' };
				if (!(act in { start: 1, stop: 1, restart: 1 }))
					return { error: 'unknown action' };
				if (act == 'stop' && ESSENTIAL[name])
					return { error: 'this service cannot be stopped from the web interface' };
				if (act == 'restart' && ESSENTIAL[name]) {
					// answer first, the restart may cut this connection
					system(sprintf('(sleep 1; %s restart) >/dev/null 2>&1 &', shq(script)));
					return { ok: true, delayed: true };
				}
				let r = sh(shq(script) + ' ' + act);
				return { ok: r.rc == 0, output: trim(r.out), running: running(SERVICES[name].proc) };
			}
		},

		autostart: {
			args: { name: '', enabled: true },
			call: function(req) {
				let name = req.args.name;
				if (!SERVICES[name] || !init_script(name)) return { error: 'unknown service' };
				if (ESSENTIAL[name] && !req.args.enabled) return { error: 'this service is always started' };
				let off = autostart_off();
				if (req.args.enabled) delete off[name]; else off[name] = true;
				let c = cursor();
				c.set('shareos', 'autostart', 'autostart');
				c.delete('shareos', 'autostart', 'disabled');
				if (length(keys(off))) c.set('shareos', 'autostart', 'disabled', sort(keys(off)));
				c.commit('shareos');
				return { ok: true, name, autostart: !off[name] };
			}
		}
	},

	'shareos.net': {
		get: {
			call: function() {
				return { ...net_settings(), ...net_state(), timeout: NET_TIMEOUT };
			}
		},

		// takes effect at once; rolled back unless confirmed within NET_TIMEOUT
		set: {
			args: { proto: '', ipaddr: '', netmask: '', gateway: '', dns: [], confirm: false },
			call: function(req) {
				let a = req.args;
				if (!a.confirm) return { error: 'confirm required' };
				if (net_state().pending) return { error: 'a network change is still waiting for confirmation' };
				if (!(a.proto in { dhcp: 1, static: 1 })) return { error: 'invalid mode' };
				let dns = filter(a.dns ?? [], (x) => x != '');
				let gw = a.gateway ?? '';
				if (a.proto == 'static') {
					if (!ip4_ok(a.ipaddr)) return { error: 'invalid IP address' };
					let pfx = mask_prefix(a.netmask);
					if (pfx == null || pfx < 8 || pfx > 30) return { error: 'invalid subnet mask' };
					let net = (x) => int(ip4_num(x) / (pow2(32 - pfx)));
					let host = ip4_num(a.ipaddr) % (pow2(32 - pfx));
					if (host == 0 || host == pow2(32 - pfx) - 1) return { error: 'the IP address is the network or broadcast address' };
					if (gw != '') {
						if (!ip4_ok(gw)) return { error: 'invalid gateway' };
						if (net(gw) != net(a.ipaddr)) return { error: 'the gateway is not in the same network' };
						if (gw == a.ipaddr) return { error: 'gateway and IP address are the same' };
					}
					if (length(dns) > 3) return { error: 'at most 3 DNS servers' };
					for (let d in dns) if (!ip4_ok(d)) return { error: 'invalid DNS server ' + d };
				}
				system('mkdir -p /etc/shareos && cp /etc/config/network ' + NET_ROLLBACK);
				let c = cursor();
				c.set('network', 'lan', 'interface');
				c.set('network', 'lan', 'ifname', 'eth0');
				c.set('network', 'lan', 'proto', a.proto);
				if (a.proto == 'static') {
					c.set('network', 'lan', 'ipaddr', a.ipaddr);
					c.set('network', 'lan', 'netmask', a.netmask);
					c.set('network', 'lan', 'gateway', gw);
					c.set('network', 'lan', 'dns', join(' ', dns));
				}
				c.commit('network');
				system(sprintf('rm -f %s/result; start-stop-daemon -S -b -x %s -- apply %d', NET_ST, NET, NET_TIMEOUT));
				return { ok: true, timeout: NET_TIMEOUT, address: a.proto == 'static' ? a.ipaddr : null };
			}
		},

		confirm: {
			call: function() {
				if (!net_state().pending) return { ok: true, pending: false };
				system(NET + ' confirm');
				return { ok: true };
			}
		}
	},



	'shareos.hw': {
		get: {
			call: function() {
				return { fan: fan_settings(), led: led_settings(), presets: FAN_PRESETS,
					temperature: read_int('/tmp/sys/temp1_input'), fan_pwm: read_int('/tmp/sys/pwm1') };
			}
		},

		set_fan: {
			args: { preset: '', off_temp: 0, full_temp: 0, half_temp: 0 },
			call: function(req) {
				let a = req.args, c = cursor();
				if (!(a.preset in { quiet: 1, balanced: 1, cool: 1, custom: 1 })) return { error: 'unknown preset' };
				c.set('shareos', 'fan', 'fan');
				c.set('shareos', 'fan', 'preset', a.preset);
				if (a.preset == 'custom') {
					let o = +a.off_temp, f = +a.full_temp, h = +a.half_temp;
					if (!(f >= 35 && f <= 70) || !(h >= 30 && h < f) || !(o == 0 || (o >= 25 && o < h)))
						return { error: 'invalid temperatures (0 or 25 <= off < half < full <= 70)' };
					c.set('shareos', 'fan', 'off_temp', '' + o);
					c.set('shareos', 'fan', 'full_temp', '' + f);
					c.set('shareos', 'fan', 'half_temp', '' + h);
				}
				c.commit('shareos');
				return { ok: true, fan: fan_settings() };
			}
		},

		set_led: {
			args: { status: '', power: '', disks: '' },
			call: function(req) {
				let a = req.args, c = cursor();
				c.set('shareos', 'led', 'led');
				if (a.status) { if (!(a.status in { heartbeat: 1, on: 1, off: 1 })) return { error: 'invalid status LED mode' }; c.set('shareos', 'led', 'status', a.status); }
				if (a.power) { if (!(a.power in { on: 1, off: 1, blink: 1 })) return { error: 'invalid power LED mode' }; c.set('shareos', 'led', 'power', a.power); }
				if (a.disks) { if (!(a.disks in { off: 1, activity: 1 })) return { error: 'invalid disk LED mode' }; c.set('shareos', 'led', 'disks', a.disks); }
				c.commit('shareos');
				sh('/usr/sbin/shareos-leds');
				return { ok: true, led: led_settings() };
			}
		}
	},

	'shareos.setup': {
		status: {
			call: function() {
				let c = cursor();
				return { done: c.get('shareos', 'setup', 'done') == '1', hostname: read_trim('/proc/sys/kernel/hostname'),
					timezone: timezone(), lang: c.get('shareos', 'ui', 'lang') ?? 'en', channel: c.get('shareos', 'update', 'channel') ?? 'stable' };
			}
		},

		zones: {
			call: function() { return { zones: zones(), current: timezone() }; }
		},

		altf: {
			call: function() { return altf_scan(); }
		},

		// first-run wizard: everything optional except marking it done
		apply: {
			args: { password: '', hostname: '', timezone: '', channel: '', altf: false },
			call: function(req) {
				let a = req.args, c = cursor(), done = [];
				if (a.altf === true) {
					let r = sh('/usr/sbin/shareos-altf import');
					for (let line in split(r.out, '\n')) {
						let m = match(line, /^imported=(.*)$/);
						if (m) push(done, 'altf:' + m[1]);
					}
				}
				if (a.hostname) { if (!set_hostname(a.hostname)) return { error: 'invalid hostname' }; push(done, 'hostname'); }
				if (a.timezone) { if (!set_timezone(a.timezone)) return { error: 'unknown time zone' }; push(done, 'timezone'); }
				if (a.channel) {
					if (!(a.channel in { stable: 1, beta: 1 })) return { error: 'invalid channel' };
					c.set('shareos', 'update', 'channel', a.channel); push(done, 'channel');
				}
				if (a.password) { let e = set_password(a.password); if (e) return { error: e }; push(done, 'password'); }
				c.set('shareos', 'setup', 'setup');
				c.set('shareos', 'setup', 'done', '1');
				c.commit('shareos');
				return { ok: true, done };
			}
		},

		reset: {
			// show the wizard again on the next login
			call: function() {
				let c = cursor();
				c.set('shareos', 'setup', 'setup');
				c.set('shareos', 'setup', 'done', '0');
				c.commit('shareos');
				return { ok: true };
			}
		}
	},

	'shareos.storage': {
		status: {
			call: function() {
				let disks = [];
				for (let d in lsblk()) {
					if (d.type != 'disk' || !match(d.name, /^sd[a-z]$/)) continue;
					d.smart = smart_read(d.name, false);
					push(disks, d);
				}
				let c = cursor();
				let swaps = [];
				for (let line in slice(split(readfile('/proc/swaps') ?? '', '\n'), 1)) {
					let f = split(trim(line), /\s+/);
					if (length(f) >= 4) push(swaps, { device: f[0], size: +f[2] * 1024, used: +f[3] * 1024 });
				}
				return {
					disks,
					swaps,
					apps: c.get('storage', 'global', 'apps'),
					arrays: mdstat(),
					volumes: volumes(),
					spindown: +(c.get('storage', 'global', 'spindown') ?? 0),
					job: storage_job()
				};
			}
		},

		smart: {
			args: { disk: '' },
			call: function(req) {
				if (!valid_disk(req.args.disk))
					return { error: 'unknown disk' };
				return smart_read(req.args.disk, true);
			}
		},

		setup: {
			// layout mirror: name + disks[2]; layout single: volumes [{name, disk}]
			args: { layout: '', name: '', disks: [], volumes: [], swap: 1024, confirm: false },
			call: function(req) {
				let a = req.args;
				if (a.confirm !== true)
					return { error: 'confirm must be true' };
				let swap = a.swap == null ? 1024 : +a.swap;
				if (!(swap >= 0 && swap <= 8192))
					return { error: 'invalid swap size' };
				let sw = '--swap=' + int(swap);
				let j = storage_job();
				if (j?.state == 'running')
					return { error: 'a storage job is already running' };
				if (a.layout == 'mirror') {
					if (!valid_name(a.name)) return { error: 'invalid name' };
					if (type(a.disks) != 'array' || length(a.disks) != 2 || a.disks[0] == a.disks[1] ||
					    !valid_disk(a.disks[0]) || !valid_disk(a.disks[1]))
						return { error: 'a mirror needs two different disks' };
					return spawn_storage([ 'setup', 'mirror', a.name, a.disks[0], a.disks[1], sw, '--yes' ]);
				}
				if (a.layout == 'single') {
					if (type(a.volumes) != 'array' || !length(a.volumes))
						return { error: 'no disks given' };
					let args = [ 'setup', 'single' ], seen = {};
					for (let v in a.volumes) {
						if (!valid_name(v?.name) || !valid_disk(v?.disk) || seen[v.name] || seen[v.disk])
							return { error: 'invalid name or disk' };
						seen[v.name] = seen[v.disk] = true;
						push(args, v.name + '=' + v.disk);
					}
					push(args, sw, '--yes');
					return spawn_storage(args);
				}
				return { error: 'unknown layout' };
			}
		},

		volume: {
			args: { name: '', action: '' },
			call: function(req) {
				let n = req.args.name, act = req.args.action;
				if (!valid_name(n)) return { error: 'invalid name' };
				if (!(act in { mount: 1, umount: 1, forget: 1 })) return { error: 'unknown action' };
				let r = sh(STORAGE + ' ' + act + ' ' + shq(n));
				if (r.rc == 0) system(USERS + ' sync >/dev/null 2>&1');
				return r.rc == 0 ? { ok: true } : { error: trim(r.out) || act + ' failed' };
			}
		},

		spindown: {
			args: { minutes: 0 },
			call: function(req) {
				let m = +req.args.minutes;
				if (m < 0 || m > 330) return { error: 'invalid value' };
				let r = sh(STORAGE + ' spindown ' + m);
				return r.rc == 0 ? { ok: true, minutes: m } : { error: trim(r.out) };
			}
		}
	},


	'shareos.accounts': {
		list: {
			call: function() { return accounts(); }
		},

		add: {
			args: { name: '', role: '', password: '', fullname: '', groups: [], home: '', quota: 0, web: true },
			call: function(req) {
				let a = req.args;
				if (!acc_name_ok(a.name)) return { error: 'invalid name (a-z, 0-9 and _, starting with a letter)' };
				if (!(a.role in { admin: 1, user: 1, share: 1 })) return { error: 'invalid role' };
				let o = { ...a }; delete o.role;
				let r = tool_result(sh_pass(sprintf('%s add %s %s %s', USERS, shq(a.name), a.role, opt_args(o)), a.password));
				return r.error ? r : { ok: true, ...accounts() };
			}
		},

		set: {
			args: { name: '', role: '', fullname: '', groups: [], home: '', quota: 0, web: true },
			call: function(req) {
				let a = req.args;
				if (!acc_name_ok(a.name)) return { error: 'invalid name' };
				let r = tool_result(sh(sprintf('%s set %s %s', USERS, shq(a.name), opt_args(a))));
				return r.error ? r : { ok: true, ...accounts() };
			}
		},

		passwd: {
			args: { name: '', password: '' },
			call: function(req) {
				let n = req.args.name;
				if (!(n == 'root' || acc_name_ok(n))) return { error: 'invalid name' };
				return tool_result(sh_pass(sprintf('%s passwd %s', USERS, shq(n)), req.args.password));
			}
		},

		del: {
			args: { name: '', remove_home: false },
			call: function(req) {
				let n = req.args.name;
				if (!acc_name_ok(n)) return { error: 'invalid name' };
				if (n == session_user(req)) return { error: 'you cannot delete your own account' };
				let r = tool_result(sh(sprintf('%s del %s%s', USERS, shq(n), req.args.remove_home ? ' --remove-home' : '')));
				return r.error ? r : { ok: true, ...accounts() };
			}
		},

		group_add: {
			args: { name: '', desc: '' },
			call: function(req) {
				let g = req.args.name;
				if (!acc_name_ok(g)) return { error: 'invalid name' };
				let r = tool_result(sh(sprintf('%s group-add %s %s', USERS, shq(g), shq('--desc=' + (req.args.desc ?? '')))));
				return r.error ? r : { ok: true, ...accounts() };
			}
		},

		group_del: {
			args: { name: '' },
			call: function(req) {
				let g = req.args.name;
				if (!acc_name_ok(g)) return { error: 'invalid name' };
				let r = tool_result(sh(sprintf('%s group-del %s', USERS, shq(g))));
				return r.error ? r : { ok: true, ...accounts() };
			}
		},

		import_altf: {
			call: function() {
				let r = sh(USERS + ' import-altf');
				if (r.rc != 0) return tool_result(r);
				let im = match(r.out, /imported=([^\n]*)/), sk = match(r.out, /skipped=([^\n]*)/);
				return { ok: true, imported: im && im[1] != '' ? split(im[1], ' ') : [], skipped: sk && sk[1] != '' ? split(sk[1], ' ') : [], ...accounts() };
			}
		}
	},

	'shareos.shares': {
		list: {
			call: function() { return share_list(); }
		},

		// create or change a share
		set: {
			args: { name: '', volume: '', path: '', comment: '', smb: true, nfs: false, guest: false,
				rw: [], ro: [], nfs_rw: false, nfs_hosts: [] },
			call: function(req) {
				let a = req.args, c = cursor();
				if (!valid_name(a.name)) return { error: 'invalid name (a-z, 0-9, - and _, max. 16)' };
				if (a.name == 'homes' || a.name == 'global' || a.name == 'ipc') return { error: 'this name is reserved' };
				if (c.get('storage', a.volume) != 'volume') return { error: 'unknown volume' };
				let path = a.path ?? a.name;
				if (path == '' || !match(path, /^[A-Za-z0-9 ._-]+(\/[A-Za-z0-9 ._-]+)*$/) || match(path, /(^|\/)\.\.?(\/|$)/))
					return { error: 'invalid folder (letters, digits, space . _ - and /)' };
				if (match(a.comment ?? '', /[\n\r\[\]]/)) return { error: 'invalid description' };
				let accs = accounts(), known = {};
				for (let u in accs.users) known[u.name] = true;
				for (let g in accs.groups) known['@' + g.name] = true;
				for (let x in [ ...(a.rw ?? []), ...(a.ro ?? []) ]) if (!known[x]) return { error: 'unknown user or group ' + x };
				for (let h in a.nfs_hosts ?? [])
					if (!match(h, /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$|^\*$|^[A-Za-z0-9.-]+$/)) return { error: 'invalid NFS client ' + h };
				c.set('shares', 'global', 'global');
				c.set('shares', a.name, 'share');
				c.set('shares', a.name, 'volume', a.volume);
				c.set('shares', a.name, 'path', path);
				c.set('shares', a.name, 'comment', a.comment ?? '');
				for (let k in [ 'smb', 'nfs', 'guest', 'nfs_rw' ]) c.set('shares', a.name, k, a[k] ? '1' : '0');
				for (let k in [ 'rw', 'ro', 'nfs_hosts' ]) {
					c.delete('shares', a.name, k);
					if (length(a[k] ?? [])) c.set('shares', a.name, k, a[k]);
				}
				c.commit('shares');
				sh(SHARES + ' apply');
				return { ok: true, ...share_list() };
			}
		},

		del: {
			args: { name: '' },
			call: function(req) {
				let c = cursor();
				if (!valid_name(req.args.name) || c.get('shares', req.args.name) != 'share') return { error: 'unknown share' };
				c.delete('shares', req.args.name);
				c.commit('shares');
				sh(SHARES + ' apply');
				return { ok: true, ...share_list() };   // the folder and its files stay
			}
		},

		global: {
			args: { workgroup: '', smb: true, nfs: true },
			call: function(req) {
				let a = req.args, c = cursor();
				c.set('shares', 'global', 'global');
				if (a.workgroup) {
					if (!match(a.workgroup, /^[A-Za-z0-9_-]{1,15}$/)) return { error: 'invalid workgroup' };
					c.set('shares', 'global', 'workgroup', uc(a.workgroup));
				}
				if (a.smb != null) c.set('shares', 'global', 'smb', a.smb ? '1' : '0');
				if (a.nfs != null) c.set('shares', 'global', 'nfs', a.nfs ? '1' : '0');
				c.commit('shares');
				sh(SHARES + ' apply');
				return { ok: true, ...share_list() };
			}
		}
	},

	'shareos.me': {
		// link this web session to the account that logged in
		bind: {
			args: { username: '', password: '' },
			call: function(req) {
				let u = req.args.username, sid = req.args.ubus_rpc_session;
				if (type(sid) != 'string' || !match(sid, /^[0-9a-f]{32}$/)) return { error: 'no session' };
				if (!(u == 'root' || acc_name_ok(u)) || !password_ok(u, req.args.password)) return { error: 'login failed' };
				system('mkdir -p ' + SESS_DIR + ' && chmod 700 ' + SESS_DIR);
				// drop links of sessions older than a week
				system('find ' + SESS_DIR + ' -type f -mtime +7 -delete 2>/dev/null');
				writefile(SESS_DIR + '/' + sid, u + '\n');
				return me_info(u);
			}
		},

		get: {
			call: function(req) {
				let u = session_user(req);
				return u ? me_info(u) : { error: 'session not bound' };
			}
		},

		passwd: {
			args: { old: '', password: '' },
			call: function(req) {
				let u = session_user(req);
				if (!u) return { error: 'session not bound' };
				if (!password_ok(u, req.args.old)) return { error: 'the current password is wrong' };
				return tool_result(sh_pass(sprintf('%s passwd %s', USERS, shq(u)), req.args.password));
			}
		}
	},

	'shareos.backup': {
		export: {
			args: { password: '' },
			call: function(req) {
				let b = backup_build();
				let text = sprintf('%J', b);
				let name = sprintf('shareos-%s-%s', b.host, replace(trim(sh('date +%Y%m%d-%H%M').out), /[^0-9-]/, ''));
				let pass = req.args.password ?? '';
				if (pass == '')
					return { filename: name + '.json', encrypted: false, content: text, ...backup_summary(b) };
				if (length(pass) < 6) return { error: 'the password needs at least 6 characters' };
				let r = crypt('enc', pass, text);
				if (r.error) return r;
				let wrap = { shareos_backup: 1, encrypted: true, cipher: 'AES-256-GCM, PBKDF2-SHA256', data: b64enc(r.data) };
				return { filename: name + '.json', encrypted: true, content: sprintf('%J', wrap), ...backup_summary(b) };
			}
		},

		// apply: false = only show what is inside
		restore: {
			args: { content: '', password: '', apply: false },
			call: function(req) {
				let j = json(req.args.content ?? '');
				if (type(j) != 'object' || j.shareos_backup != 1) return { error: 'not a ShareOS settings backup' };
				if (j.encrypted) {
					if (!req.args.password) return { error: 'password required', encrypted: true };
					let r = crypt('dec', req.args.password, b64dec(j.data ?? '') ?? '');
					if (r.error) return { ...r, encrypted: true };
					j = json(r.data);
					if (type(j) != 'object' || j.shareos_backup != 1) return { error: 'damaged backup' };
				}
				if (!req.args.apply) return { ok: true, preview: true, encrypted: !!req.args.password, ...backup_summary(j) };
				return backup_restore(j);
			}
		}
	},

	'shareos.update': {
		check: {
			args: { channel: 'stable' },
			call: function(req) {
				let ch = req.args.channel;
				return run_updater(ch ? [ 'check', ch ] : [ 'check' ]);
			}
		},

		status: {
			call: function() {
				return run_updater([ 'status' ]);
			}
		},

		download: {
			args: { tag: '' },
			call: function(req) {
				if (!req.args.tag)
					return { error: 'tag missing' };
				let s = run_updater([ 'status' ]);
				if (s.state == 'downloading' || s.state == 'verifying' || s.state == 'flashing')
					return { error: 'busy: ' + s.state };
				return spawn_updater([ 'download', req.args.tag ]);
			}
		},

		apply: {
			// "confirm" must be true: flashing is the one step that cannot be undone
			args: { tag: '', confirm: false },
			call: function(req) {
				if (req.args.confirm !== true)
					return { error: 'confirm must be true' };
				let s = run_updater([ 'status' ]);
				if (s.state != 'ready' || s.release?.tag != req.args.tag)
					return { error: 'release not downloaded and verified' };
				return spawn_updater([ 'apply', req.args.tag ]);
			}
		},

		cancel: {
			call: function() {
				return run_updater([ 'cancel' ]);
			}
		}
	}
};
