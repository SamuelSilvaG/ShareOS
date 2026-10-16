// ShareOS rpcd plugin: ubus objects used by the web interface.
//
//   shareos.system  info | reboot
//   shareos.update  check | status | download | apply | cancel
//
// Long-running update steps run as a separate process (shareos-update) so
// rpcd's main loop is never blocked; the UI polls shareos.update.status.
'use strict';

import { readfile, popen, glob, readlink, stat } from 'fs';

const UPDATER = '/usr/sbin/shareos-update';

function shq(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
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

function ipv4(ifname) {
	let p = popen('ip -4 -o addr show dev ' + shq(ifname) + ' 2>/dev/null');
	let o = p ? p.read('all') : '';
	p?.close();
	let m = match(o ?? '', /inet ([0-9.]+)\/([0-9]+)/);
	return m ? { address: m[1], prefix: +m[2] } : null;
}

function run_updater(args) {
	let p = popen(join(' ', [ UPDATER, ...map(args, shq) ]) + ' 2>/dev/null');
	if (!p)
		return { state: 'error', error: 'cannot start updater' };
	let out = p.read('all');
	p.close();
	let res = json(out ?? '');
	return type(res) == 'object' ? res : { state: 'error', error: 'updater returned no result' };
}

function spawn_updater(args) {
	// detached, so the ubus call returns at once
	system(sprintf('start-stop-daemon -S -b -x %s -- %s', UPDATER, join(' ', map(args, shq))));
	return { started: true };
}

return {
	'shareos.system': {
		info: {
			call: function() {
				let up = split(read_trim('/proc/uptime') ?? '0', ' ');
				let load = split(read_trim('/proc/loadavg') ?? '', ' ');
				return {
					model: read_trim('/proc/device-tree/model'),
					release: release(),
					hostname: read_trim('/proc/sys/kernel/hostname'),
					kernel: read_trim('/proc/sys/kernel/osrelease'),
					uptime: +up[0],
					load: [ +load[0], +load[1], +load[2] ],
					memory: meminfo(),
					temperature: read_int('/tmp/sys/temp1_input'),   // m°C, from dns320l-daemon
					fan_pwm: read_int('/tmp/sys/pwm1'),
					network: {
						eth0: {
							ipv4: ipv4('eth0'),
							speed: read_int('/sys/class/net/eth0/speed'),
							mac: read_trim('/sys/class/net/eth0/address')
						}
					},
					disks: disks()
				};
			}
		},

		reboot: {
			call: function() {
				system('(sleep 2; reboot) >/dev/null 2>&1 &');
				return { rebooting: true };
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
