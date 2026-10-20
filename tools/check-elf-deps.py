#!/usr/bin/env python3
"""
Checks that every ELF program and library in a target folder finds the
shared libraries it needs (DT_NEEDED) in /lib or /usr/lib of that folder.
Run by board/dlink/dns320l/post-build.sh after unused parts are removed.

    tools/check-elf-deps.py <target-dir>
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sysapps'))
from pack import needed   # 32-bit ELF reader of the system app packer

root = sys.argv[1]
have = set()
for d in ('lib', 'usr/lib'):
    for n in os.listdir(os.path.join(root, d)):
        have.add(n)
missing = []
for base, dirs, files in os.walk(root):
    for f in files:
        p = os.path.join(base, f)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        with open(p, 'rb') as h:
            if h.read(4) != b'\x7fELF':
                continue
        try:
            libs = needed(p)
        except SystemExit:
            continue      # not a 32-bit LE ELF (e.g. a host tool) – not ours
        for n in libs:
            if n not in have:
                missing.append('%s needs %s' % (os.path.relpath(p, root), n))
if missing:
    sys.exit('missing libraries in the target:\n  ' + '\n  '.join(sorted(missing)))
print('check-elf-deps: all libraries found')
