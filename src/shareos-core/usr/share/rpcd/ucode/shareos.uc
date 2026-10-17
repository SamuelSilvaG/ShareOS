// ShareOS rpcd plugin: ubus objects used by the web interface.
//
//   shareos.system   info | log | reboot | poweroff | factory_reset |
//                    set_password | set_hostname
//   shareos.service  list | action
//   shareos.update   check | status | download | apply | cancel
//
// Long-running update steps run as a separate process (shareos-update) so
// rpcd's main loop is never blocked; the UI polls shareos.update.status.
'use strict';

import { readfile, writefile, popen, glob, stat, readlink, symlink, unlink } from 'fs';
import { cursor } from 'uci';

const UPDATER = '/usr/sbin/shareos-update';

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

function lsblk() {
	let r = sh('lsblk -J -b -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL,SERIAL,TRAN,RM,ROTA');
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
		let dev = s.uuid ? trim(sh('blkid -U ' + shq(s.uuid)).out) : null;
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

function ui_settings() {
	let c = cursor();
	return { lang: c.get('shareos', 'ui', 'lang') ?? 'en', logo: (c.get('shareos', 'ui', 'logo') ?? '1') != '0' };
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

return {
	'shareos.ui': {
		// public (also before login): language and logo for the login page
		get: {
			call: function() { return ui_settings(); }
		},

		set: {
			args: { lang: '', logo: false },
			call: function(req) {
				let c = cursor();
				if (req.args.lang != null && req.args.lang != '') {
					if (!match(req.args.lang, /^[a-z]{2}(-[A-Za-z]{2})?$/)) return { error: 'invalid language' };
					c.set('shareos', 'ui', 'lang', req.args.lang);
				}
				if (req.args.logo != null)
					c.set('shareos', 'ui', 'logo', req.args.logo ? '1' : '0');
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
					push(list, { name, label: s.label, desc: s.desc, running: running(s.proc), essential: !!ESSENTIAL[name] });
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
