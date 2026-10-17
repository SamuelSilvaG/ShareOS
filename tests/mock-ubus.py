#!/usr/bin/env python3
"""
Serves the web interface (src/shareos-core/www) with a fake /ubus endpoint,
for UI work, screenshots and translation checks without a box or emulator.

    python3 tests/mock-ubus.py [port]      -> http://127.0.0.1:8200/  (root / shareos)

The data imitates a DNS-320L with two disks, a mirror in initial sync and an
update available.
"""
import json
import os
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WWW = Path(__file__).resolve().parent.parent / 'src/shareos-core/www'
SID = 'c0ffee00c0ffee00c0ffee00c0ffee00'
T0 = time.time()
STATE = {'setup_done': False, 'fan': {'preset': 'balanced', 'off_temp': 0, 'full_temp': 50, 'half_temp': 45}, 'led': {'status': 'heartbeat', 'power': 'on', 'disks': 'off'}, 'logo': True, 'lang': 'en', 'channel': 'beta', 'job': None, 'https': True, 'redirect': False, 'theme': 'dark', 'accent': 'blue', 'autostart_off': ['crond'],
         'users': {'jan': {'role': 'admin', 'fullname': 'Jan', 'groups': ['familie'], 'home': 'daten', 'quota': 0, 'web': True, 'pw': 'shareos'},
                   'anna': {'role': 'user', 'fullname': 'Anna', 'groups': ['familie'], 'home': 'daten', 'quota': 200000, 'web': True, 'pw': 'anna123'},
                   'tv': {'role': 'share', 'fullname': 'Fernseher', 'groups': ['medien'], 'home': '', 'quota': 0, 'web': True, 'pw': 'tv1234'}},
         'groups': {'familie': 'Familie', 'medien': 'Mediengeräte'},
         'shares': {'fotos': {'volume': 'daten', 'path': 'Fotos', 'comment': 'Familienfotos', 'smb': True, 'nfs': False, 'guest': False, 'rw': ['jan'], 'ro': ['@familie'], 'nfs_rw': False, 'nfs_hosts': []},
                    'medien': {'volume': 'daten', 'path': 'Medien', 'comment': 'Filme und Musik', 'smb': True, 'nfs': True, 'guest': True, 'rw': ['jan'], 'ro': ['@medien'], 'nfs_rw': False, 'nfs_hosts': ['10.241.1.0/24']}},
         'sessions': {},
         'net': {'proto': 'dhcp', 'ipaddr': '', 'netmask': '255.255.255.0', 'gateway': '', 'dns': []}, 'net_pending': None}

DISK = lambda n, model, serial: {
    'name': n, 'type': 'disk', 'size': 4000787030016, 'model': model, 'serial': serial, 'tran': 'sata', 'rm': False, 'rota': True,
    'children': [
        {'name': n + '1', 'type': 'part', 'size': 1073741824, 'fstype': 'swap', 'label': 'shareos-swap'},
        {'name': n + '2', 'type': 'part', 'size': 3999713288192, 'fstype': 'linux_raid_member', 'label': 'shareos:daten',
         'children': [{'name': 'md0', 'type': 'raid1', 'fstype': 'ext4', 'label': 'daten', 'mountpoint': '/mnt/daten'}]}],
    'smart': {'passed': True, 'temperature': 38, 'power_on_hours': 18234, 'reallocated': 0, 'pending': 0, 'uncorrectable': 0}}


def info():
    up = time.time() - T0 + 5 * 86400
    return {
        'model': 'D-Link DNS-320L-rev-Ax NAS', 'hostname': 'skynet-nas', 'kernel': '6.18.57', 'boot': 'flash',
        'release': {'version': '0.1.0-beta.1', 'board': 'dns320l', 'fwname': 'DNS-320L-rev-Ax', 'stage': 'beta'},
        'time': int(time.time()), 'uptime': up, 'load': [0.42, 0.38, 0.35],
        'cpu': {'total': int(up * 100), 'idle': int(up * 85)},
        'memory': {'memtotal': 253092 * 1024, 'memavailable': 160000 * 1024},
        'temperature': 41000, 'fan_pwm': 100,
        'network': {'eth0': {'ipv4': {'address': '10.241.1.106', 'prefix': 24}, 'gateway': '10.241.1.1', 'dns': ['10.243.1.100'],
                             'speed': 1000, 'mac': 'c4:a8:1d:81:f3:c2', 'rx_bytes': int(up * 2_000_000), 'tx_bytes': int(up * 150_000)}},
        'filesystems': [
            {'source': 'ubi0:rootfs_data', 'mount': '/overlay', 'size': 46 << 20, 'used': 3 << 20, 'avail': 43 << 20},
            {'source': '/dev/ubiblock0_0', 'mount': '/rom', 'size': 9 << 20, 'used': 9 << 20, 'avail': 0},
            {'source': 'tmpfs', 'mount': '/tmp', 'size': 123 << 20, 'used': 1 << 20, 'avail': 122 << 20}],
        'disks': [{'name': 'sda', 'model': 'WDC WD40EFPX', 'size': 4000787030016, 'removable': False},
                  {'name': 'sdb', 'model': 'WDC WD40EFPX', 'size': 4000787030016, 'removable': False}]}


def storage():
    pct = min(99.9, 12.4 + (time.time() - T0) / 60)
    return {
        'disks': [DISK('sda', 'WDC WD40EFPX-68C6CN0', 'WD-WX12A3456789'), DISK('sdb', 'WDC WD40EFPX-68C6CN0', 'WD-WX98B7654321')],
        'swaps': [{'device': '/dev/sda1', 'size': 1 << 30, 'used': 12 << 20}, {'device': '/dev/sdb1', 'size': 1 << 30, 'used': 11 << 20}],
        'apps': 'daten',
        'arrays': {'md0': {'name': 'md0', 'state': 'active', 'level': 'raid1', 'members': ['sdb2', 'sda2'], 'disks': 2, 'active': 2,
                           'health': 'UU', 'sync': {'action': 'resync', 'percent': pct, 'finish': '412.5min'}}},
        'volumes': [{'name': 'daten', 'uuid': '1b4e28ba-2fa1-11d2-883f-0016d3cca427', 'fstype': 'ext4', 'layout': 'mirror', 'enabled': True,
                     'device': '/dev/md0', 'mountpoint': '/mnt/daten', 'mounted': True, 'size': 3936 << 30, 'used': 1210 << 30, 'avail': 2726 << 30}],
        'spindown': 20, 'job': STATE['job']}


SERVICES = [('board', 'Gerätesteuerung', 'Lüfter, Temperatur, Taster, MCU-Uhr', True), ('crond', 'Zeitplaner', 'cron', False),
            ('dropbear', 'SSH / SFTP', 'Dropbear, Port 22', False), ('ntpd', 'Zeit (NTP)', 'stellt die Uhr, gleicht die MCU-Uhr ab', False),
            ('rpcd', 'API (rpcd)', 'Schnittstelle für diese Oberfläche', True), ('syslogd', 'Systemprotokoll', 'syslogd, im RAM', False),
            ('ubus', 'Systembus (ubus)', 'Nachrichten zwischen den Diensten', True), ('uhttpd', 'Weboberfläche', 'uhttpd, Port 80', True)]

RELEASES = [{'tag': 'v0.2.0-beta.1', 'version': '0.2.0-beta.1', 'prerelease': True, 'date': '2026-10-24T10:00:00Z', 'size': 8396800,
             'url': 'https://github.com/UniqueDroid/ShareOS/releases', 'notes': '- Freigaben (SMB, NFS)\n- Benutzer und Gruppen\n- Speicher-Assistent'},
            {'tag': 'v0.1.0-beta.1', 'version': '0.1.0-beta.1', 'prerelease': True, 'date': '2026-10-17T16:00:00Z', 'size': 8392704,
             'url': 'https://github.com/UniqueDroid/ShareOS/releases', 'notes': 'Erste Testversion'}]


def accounts():
    u = STATE['users']
    users = [{'name': n, 'role': x['role'], 'fullname': x['fullname'], 'uid': 1000 + k, 'groups': x['groups'], 'home': x['home'],
              'quota': x['quota'], 'web': x['web'],
              'usage': [{'volume': 'daten', 'used': (k + 1) * 37_000_000_000, 'limit': x['quota'] * 1000000}] if x['home'] else []}
             for k, (n, x) in enumerate(sorted(u.items()))]
    groups = [{'name': g, 'desc': d, 'members': [n for n, x in u.items() if g in x['groups']]} for g, d in sorted(STATE['groups'].items())]
    return {'users': users, 'groups': groups}


def shares():
    return {'shares': [{'name': n, **x, 'fullpath': f"/mnt/{x['volume']}/{x['path']}", 'mounted': True} for n, x in sorted(STATE['shares'].items())],
            'workgroup': 'WORKGROUP', 'smb_enabled': True, 'nfs_enabled': True, 'smb_running': True, 'nfs_running': True}


def me(user):
    if user == 'root':
        return {'name': 'root', 'role': 'admin', 'fullname': 'Administrator', 'groups': [], 'quota': 0, 'home': None, 'usage': [], 'shares': [], 'host': 'skynet-nas'}
    x = STATE['users'][user]
    mine = []
    for n, sh in sorted(STATE['shares'].items()):
        tags = [user] + ['@' + g for g in x['groups']]
        acc = 'rw' if any(t in sh['rw'] for t in tags) else 'ro' if any(t in sh['ro'] for t in tags) or sh['guest'] else None
        if acc:
            mine.append({'name': n, 'access': acc, 'comment': sh['comment']})
    return {'name': user, 'role': x['role'], 'fullname': x['fullname'], 'groups': x['groups'], 'quota': x['quota'],
            'home': {'volume': x['home'], 'path': f"/mnt/{x['home']}/home/{user}", 'smb': user} if x['home'] else None,
            'usage': [{'volume': 'daten', 'used': 61_500_000_000, 'limit': x['quota'] * 1000000}], 'shares': mine, 'host': 'skynet-nas'}


def call(obj, method, args):
    if obj == 'session' and method == 'login':
        user, pw = args.get('username'), args.get('password')
        if user == 'root' and pw == 'shareos':
            return {'ubus_rpc_session': SID}
        x = STATE['users'].get(user)
        if x and x['pw'] == pw and (x['role'] == 'admin' or (x['role'] == 'user' and x['web'])):
            return {'ubus_rpc_session': SID}
        return 6
    if obj == 'shareos.me':
        if method == 'bind':
            STATE['sessions'][SID] = args['username']
        u = STATE['sessions'].get(SID, 'root')
        if method == 'passwd':
            return {'ok': True}
        return me(u)
    if obj == 'shareos.accounts':
        if method == 'add':
            STATE['users'][args['name']] = {'role': args['role'], 'fullname': args.get('fullname', ''), 'groups': args.get('groups', []),
                                            'home': args.get('home', ''), 'quota': args.get('quota', 0), 'web': args.get('web', True), 'pw': args.get('password')}
        if method == 'set':
            STATE['users'][args['name']].update({k: v for k, v in args.items() if k != 'name'})
        if method == 'del':
            STATE['users'].pop(args['name'], None)
        if method == 'group_add':
            STATE['groups'][args['name']] = args.get('desc', '')
        if method == 'group_del':
            STATE['groups'].pop(args['name'], None)
        if method == 'import_altf':
            return {'ok': True, 'imported': [], 'skipped': [], **accounts()}
        return accounts() if method != 'passwd' else {'ok': True}
    if obj == 'shareos.backup':
        summary = {'version': '0.1.0-beta.2', 'host': 'skynet-nas', 'created': int(time.time()), 'users': sorted(STATE['users']),
                   'shares': sorted(STATE['shares']), 'configs': ['shareos', 'storage', 'network', 'accounts', 'shares'], 'certificate': True}
        if method == 'export':
            enc = bool(args.get('password'))
            return {'filename': 'shareos-skynet-nas-20261017-2330.json', 'encrypted': enc,
                    'content': json.dumps({'shareos_backup': 1, 'encrypted': True, 'data': 'U09TMQ=='} if enc else {'shareos_backup': 1, **summary}), **summary}
        try:
            d = json.loads(args.get('content') or '')
        except ValueError:
            return {'error': 'not a ShareOS settings backup'}
        if d.get('encrypted') and not args.get('password'):
            return {'error': 'password required', 'encrypted': True}
        return {'ok': True, 'reboot': True} if args.get('apply') else {'ok': True, 'preview': True, **summary}
    if obj == 'shareos.shares':
        if method == 'set':
            STATE['shares'][args['name']] = {k: v for k, v in args.items() if k != 'name'}
        if method == 'del':
            STATE['shares'].pop(args['name'], None)
        return shares()
    if obj == 'session':
        return {}
    if obj == 'shareos.ui':
        if method == 'set':
            if args.get('lang'):
                STATE['lang'] = args['lang']
            if 'logo' in args:
                STATE['logo'] = bool(args['logo'])
            for k in ('theme', 'accent'):
                if args.get(k):
                    STATE[k] = args[k]
        return {'lang': STATE['lang'], 'logo': STATE['logo'], 'theme': STATE['theme'], 'accent': STATE['accent']}
    if obj == 'shareos.net':
        if method == 'set':
            STATE['net'] = {k: args.get(k, STATE['net'][k]) for k in STATE['net']}
            STATE['net_pending'] = time.time() + 120
            return {'ok': True, 'timeout': 120}
        if method == 'confirm':
            STATE['net_pending'] = None
            return {'ok': True}
        p = STATE['net_pending']
        return {**STATE['net'], 'timeout': 120, 'result': None,
                'pending': {'until': int(p), 'left': max(0, int(p - time.time()))} if p else None}
    if obj == 'shareos.setup':
        if method == 'status':
            return {'done': STATE['setup_done'], 'hostname': 'shareos', 'timezone': 'Europe/Berlin', 'lang': STATE['lang'], 'channel': 'stable'}
        if method == 'zones':
            return {'zones': ['Europe/Berlin', 'Europe/London', 'Europe/Vienna', 'Europe/Zurich', 'America/New_York', 'UTC'], 'current': 'Europe/Berlin'}
        if method == 'altf':
            return {'found': True, 'file': 'set_2026-07-23_15:20:02.tgz', 'date': '2026-07-23 15:20:02', 'hostname': 'skynet-nas',
                    'timezone': 'Europe/Berlin', 'users': ['jan:Jan', 'media:Medien'], 'shares': ['Fotos', 'Musik', 'Backup'], 'nfs': ['/mnt/md0/proxmox'], 'fan_lo_temp': '45'}
        if method in ('apply',):
            STATE['setup_done'] = True
            return {'ok': True, 'done': []}
        if method == 'reset':
            STATE['setup_done'] = False
        return {'ok': True}
    if obj == 'shareos.hw':
        if method == 'set_fan':
            STATE['fan'].update(args)
        if method == 'set_led':
            STATE['led'].update({k: v for k, v in args.items() if v})
        return {'fan': STATE['fan'], 'led': STATE['led'], 'temperature': 41000, 'fan_pwm': 100,
                'presets': {'quiet': {'off_temp': 40, 'full_temp': 55, 'half_temp': 50}}}
    if obj == 'shareos.web':
        if method == 'set':
            STATE.update({k: v for k, v in args.items() if k in ('https', 'redirect')})
        return {'https': STATE['https'], 'redirect': STATE['redirect'], 'cert': {
            'subject': 'CN=skynet-nas, O=ShareOS', 'issuer': 'CN=skynet-nas, O=ShareOS', 'from': '2026-10-17 00:00:00',
            'until': '2036-10-17 23:59:59', 'san': ['dNSName:skynet-nas', 'dNSName:skynet-nas.local', 'iPAddress:10.241.1.106'], 'selfsigned': True}}
    if obj == 'shareos.system':
        if method == 'info':
            return info()
        if method == 'log':
            return {'lines': ['Oct 17 16:00:01 skynet-nas syslog.info syslogd started', 'Oct 17 16:00:05 skynet-nas user.notice shareos: ready']}
        return {'ok': True}
    if obj == 'shareos.service':
        if method == 'list':
            return {'services': [{'name': n, 'label': l, 'desc': d, 'running': n not in STATE['autostart_off'], 'essential': e,
                                  'autostart': n not in STATE['autostart_off']} for n, l, d, e in SERVICES]}
        if method == 'autostart':
            off = set(STATE['autostart_off'])
            (off.discard if args.get('enabled') else off.add)(args['name'])
            STATE['autostart_off'] = sorted(off)
            return {'ok': True, 'name': args['name'], 'autostart': bool(args.get('enabled'))}
        return {'ok': True}
    if obj == 'shareos.storage':
        if method == 'status':
            return storage()
        return {'ok': True}
    if obj == 'shareos.update':
        if method == 'apply':
            STATE['apply_t'] = time.time()
            return {'started': True}
        rel = {'tag': 'v0.2.0-beta.1', 'version': '0.2.0-beta.1'}
        if method == 'status' and STATE.get('apply_t') and time.time() - STATE['apply_t'] < 2:
            # like the real updater: just after the click it may still report 'ready'
            return {'state': 'ready', 'current': '0.1.0-beta.1', 'release': rel}
        if method == 'status' and STATE.get('apply_t'):
            # walk through the flashing steps, 3 s each
            steps = ['check bundle', 'stage rootfs', 'erase ramdisk', 'write ramdisk', 'verify ramdisk', 'erase uImage', 'write uImage', 'verify uImage']
            i = int((time.time() - STATE['apply_t'] - 2) / 3)
            if i < len(steps):
                return {'state': 'flashing', 'step': steps[i], 'current': '0.1.0-beta.1', 'release': rel}
            return {'state': 'flashed', 'current': '0.1.0-beta.1', 'release': rel, 'pending_reboot': True}
        if method == 'status' and os.environ.get('MOCK_UPDATE_READY'):
            return {'state': 'ready', 'current': '0.1.0-beta.1', 'release': rel}
        check = {'time': int(time.time()), 'channel': STATE['channel'], 'repo': 'UniqueDroid/ShareOS', 'releases': RELEASES,
                 'latest': 'v0.2.0-beta.1', 'update_available': True}
        if method == 'check':
            return {'current': '0.1.0-beta.1', 'fwname': 'DNS-320L-rev-Ax', **check}
        return {'state': 'idle', 'current': '0.1.0-beta.1', 'check': check, 'last_upgrade': 'ok 0.1.0-beta.1'}
    if obj == 'uci':
        if method == 'get':
            return {'values': {}}
        if method == 'set' and args.get('section') == 'update':
            STATE['channel'] = args['values'].get('channel', STATE['channel'])
        return {}
    return 3


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WWW), **kw)

    def log_message(self, *a):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers['Content-Length'])) or b'{}')
        params = req.get('params', [])
        if req.get('method') == 'call':
            sid, obj, method, args = params
            if obj not in ('session',) and not (obj == 'shareos.ui' and method == 'get') and sid != SID:
                body = {'jsonrpc': '2.0', 'id': req.get('id'), 'error': {'code': -32002, 'message': 'Access denied'}}
            else:
                r = call(obj, method, args)
                body = {'jsonrpc': '2.0', 'id': req.get('id'), 'result': [r] if isinstance(r, int) else [0, r]}
        else:
            body = {'jsonrpc': '2.0', 'id': req.get('id'), 'result': {}}
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8200
    print(f'http://127.0.0.1:{port}/  (root / shareos)')
    ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
