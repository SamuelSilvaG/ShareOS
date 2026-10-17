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

import { readfile, writefile, popen, glob, stat } from 'fs';

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

return {
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
