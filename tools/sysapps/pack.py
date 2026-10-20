#!/usr/bin/env python3
"""
Pack the system apps (sysapps/<id>/) as .sapp from a buildroot target.

    tools/sysapps/pack.py <target-dir> <out-dir> [id ...]

<target-dir>  output/sysapps/target (make sysapps)
<out-dir>     gets <id>-<version>.sapp and .sapp.sha256

Package layout (tar.gz, reproducible: sorted, owner 0, fixed time):
    app.json  icon.svg  bin/<program>  lib/<library>  share/<folder>/…
Libraries: every DT_NEEDED of the programs (and of those libraries) that the
firmware does not have (FIRMWARE_TARGET, default output/dns320l/target) is
taken from <target-dir>. Links are resolved – a package has regular files only.
"""
import gzip, hashlib, io, json, os, re, struct, sys, tarfile

TOP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RECIPES = os.path.join(TOP, 'sysapps')
CMD_RE = re.compile(r'^[a-z0-9][a-z0-9._+-]{0,31}$')
LIB_DIRS = ('lib', 'usr/lib')


def needed(path):
    """DT_NEEDED entries of a 32-bit little-endian ELF file (ARM)."""
    with open(path, 'rb') as f:
        d = f.read()
    if d[:4] != b'\x7fELF' or d[4] != 1 or d[5] != 1:
        raise SystemExit('%s: not a 32-bit little-endian ELF file' % path)
    shoff, = struct.unpack_from('<I', d, 0x20)
    shentsize, shnum = struct.unpack_from('<HH', d, 0x2e)
    secs = [struct.unpack_from('<IIIIIIIIII', d, shoff + i * shentsize) for i in range(shnum)]
    dyn = [s for s in secs if s[1] == 6]          # SHT_DYNAMIC
    if not dyn:
        return []
    _, _, _, _, off, size, link, _, _, _ = dyn[0]
    stroff = secs[link][4]
    out = []
    for i in range(0, size, 8):
        tag, val = struct.unpack_from('<iI', d, off + i)
        if tag == 0: break
        if tag == 1:                               # DT_NEEDED
            end = d.index(b'\0', stroff + val)
            out.append(d[stroff + val:end].decode())
    return out


def find_lib(root, name):
    for ld in LIB_DIRS:
        p = os.path.join(root, ld, name)
        if os.path.exists(p):
            return p
    return None


def libs_for(progs, target, firmware):
    todo, have = list(progs), {}
    while todo:
        for n in needed(todo.pop()):
            if n in have or find_lib(firmware, n):
                continue
            p = find_lib(target, n)
            if not p:
                raise SystemExit('library %s is neither in the firmware nor in %s' % (n, target))
            have[n] = os.path.realpath(p)
            todo.append(have[n])
    return have


def build(rid, target, firmware, out):
    rdir = os.path.join(RECIPES, rid)
    a = json.load(open(os.path.join(rdir, 'app.json'), encoding='utf-8'))
    spec = json.load(open(os.path.join(rdir, 'pack.json'), encoding='utf-8'))
    if a.get('id') != rid or a.get('type') != 'system':
        raise SystemExit('%s: id must match the folder, type must be "system"' % rid)
    files = {}                                     # name in package -> source
    progs = []
    for b in spec.get('bin', []):
        p = os.path.join(target, b)
        if not os.path.isfile(p):
            raise SystemExit('%s: %s missing – is its package enabled in configs/shareos_sysapps_defconfig?' % (rid, b))
        files['bin/' + os.path.basename(b)] = os.path.realpath(p)
        progs.append(os.path.realpath(p))
    for c in a.get('commands', []):
        if not CMD_RE.match(c) or 'bin/' + c not in files:
            raise SystemExit('%s: command %s is not a program of the package' % (rid, c))
    for n, p in sorted(libs_for(progs, target, firmware).items()):
        files['lib/' + n] = p
    for s in spec.get('share', []):
        base = os.path.join(target, s)
        if not os.path.isdir(base):
            raise SystemExit('%s: folder %s missing' % (rid, s))
        for root, dirs, names in os.walk(base, followlinks=True):
            for n in names:
                p = os.path.join(root, n)
                files['share/%s/%s' % (os.path.basename(s), os.path.relpath(p, base))] = os.path.realpath(p)
    if a.get('icon'):
        files[a['icon']] = os.path.join(rdir, a['icon'])

    buf = io.BytesIO()
    dirs = sorted({os.path.dirname(n) for n in files if '/' in n} |
                  {'/'.join(n.split('/')[:i]) for n in files for i in range(1, n.count('/'))})

    def ti(name, size, mode, kind=tarfile.REGTYPE):
        t = tarfile.TarInfo(name)
        t.size, t.mode, t.type, t.mtime = size, mode, kind, 0
        t.uid = t.gid = 0; t.uname = t.gname = 'root'
        return t

    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tar:
        aj = (json.dumps(a, ensure_ascii=False, indent='\t') + '\n').encode()
        tar.addfile(ti('app.json', len(aj), 0o644), io.BytesIO(aj))
        for d in dirs:
            tar.addfile(ti(d, 0, 0o755, tarfile.DIRTYPE))
        for n in sorted(files):
            data = open(files[n], 'rb').read()
            exe = n.startswith('bin/') or n.startswith('lib/')
            tar.addfile(ti(n, len(data), 0o755 if exe else 0o644), io.BytesIO(data))
    data = gzip.compress(buf.getvalue(), compresslevel=9, mtime=0)
    name = '%s-%s.sapp' % (rid, a['version'])
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, name), 'wb').write(data)
    sha = hashlib.sha256(data).hexdigest()
    open(os.path.join(out, name + '.sha256'), 'w').write('%s  %s\n' % (sha, name))
    print('%s  %s  %d bytes  (%s)' % (name, sha, len(data), ', '.join(sorted(n for n in files if not n.startswith('share/')))))


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    target, out = sys.argv[1], sys.argv[2]
    firmware = os.environ.get('FIRMWARE_TARGET', os.path.join(TOP, 'output', 'dns320l', 'target'))
    if not os.path.isdir(os.path.join(firmware, 'lib')):
        raise SystemExit('firmware target %s missing – run make dns320l first' % firmware)
    ids = sys.argv[3:] or sorted(d for d in os.listdir(RECIPES) if os.path.isfile(os.path.join(RECIPES, d, 'pack.json')))
    for i in ids:
        build(i, target, firmware, out)


if __name__ == '__main__':
    main()
