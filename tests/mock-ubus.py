#!/usr/bin/env python3
"""
Serves the web interface (src/shareos-core/www) with a fake /ubus endpoint,
for UI work, screenshots and translation checks without a box or emulator.

    python3 tests/mock-ubus.py [port]      -> http://127.0.0.1:8200/  (root / shareos)

The data imitates a DNS-320L with two disks, a mirror in initial sync and an
update available.
"""
import json
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WWW = Path(__file__).resolve().parent.parent / 'src/shareos-core/www'
SID = 'c0ffee00c0ffee00c0ffee00c0ffee00'
T0 = time.time()
STATE = {'setup_done': False, 'fan': {'preset': 'balanced', 'off_temp': 0, 'full_temp': 50, 'half_temp': 45}, 'led': {'status': 'heartbeat', 'power': 'on', 'disks': 'off'}, 'logo': True, 'lang': 'en', 'channel': 'beta', 'job': None, 'https': True, 'redirect': False}

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


def call(obj, method, args):
    if obj == 'session' and method == 'login':
        return {'ubus_rpc_session': SID} if args.get('password') == 'shareos' else 6
    if obj == 'session':
        return {}
    if obj == 'shareos.ui':
        if method == 'set':
            if args.get('lang'):
                STATE['lang'] = args['lang']
            if 'logo' in args:
                STATE['logo'] = bool(args['logo'])
        return {'lang': STATE['lang'], 'logo': STATE['logo']}
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
            return {'services': [{'name': n, 'label': l, 'desc': d, 'running': True, 'essential': e} for n, l, d, e in SERVICES]}
        return {'ok': True}
    if obj == 'shareos.storage':
        if method == 'status':
            return storage()
        return {'ok': True}
    if obj == 'shareos.update':
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
