#!/usr/bin/env python3
"""Build i18n/<code>.json from en.json and a translation list.

  tools/i18n/build-lang.py <code> <name> <translations.tsv>

en.json is the reference: same German keys and patterns, the values come
from the TSV (lines "E<n>\\ttext", "P<n>\\ttext", "W<n>\\ttext"; numbers as
printed by  tools/i18n/build-lang.py --list). Missing entries fall back to
English. Placeholders ($1, $2 …) must match the English text.
"""
import json
import re
import sys
from collections import OrderedDict

WWW = 'src/shareos-core/www/i18n/'


def load_en():
    return json.load(open(WWW + 'en.json', encoding='utf-8'), object_pairs_hook=OrderedDict)


if sys.argv[1:2] == ['--list']:
    en = load_en()
    for i, v in enumerate(en['exact'].values()):
        print(f'E{i}\t{v}')
    for i, p in enumerate(en['patterns']):
        print(f'P{i}\t{p[1]}')
    for i, w in enumerate(en['words']):
        print(f'W{i}\t{w[1]}\t[{w[0]}]')
    sys.exit(0)

code, name, tsv = sys.argv[1:4]
en = load_en()
tr = {}
for line in open(tsv, encoding='utf-8'):
    line = line.rstrip('\n')
    if not line or line.startswith('#'):
        continue
    k, _, v = line.partition('\t')
    tr[k] = v

ph = re.compile(r'\$\d')
errors = []


def pick(key, english):
    v = tr.get(key)
    if v is None:
        return english
    if sorted(ph.findall(v)) != sorted(ph.findall(english)):
        errors.append(f'{key}: placeholders differ: {english!r} -> {v!r}')
        return english
    return v


out = OrderedDict(language=code, name=name, source='de')
out['exact'] = OrderedDict((k, pick(f'E{i}', v)) for i, (k, v) in enumerate(en['exact'].items()))
out['patterns'] = [[p[0], pick(f'P{i}', p[1])] for i, p in enumerate(en['patterns'])]
out['words'] = [[w[0], pick(f'W{i}', w[1])] + w[2:] for i, w in enumerate(en['words'])]
if errors:
    print('\n'.join(errors))
    sys.exit(1)
missing = [f'E{i}' for i in range(len(en['exact'])) if f'E{i}' not in tr]
open(WWW + code + '.json', 'w', encoding='utf-8').write(json.dumps(out, ensure_ascii=False, indent='\t') + '\n')
print(f'{code}: {len(tr)} entries, {len(missing)} exact texts fall back to English')
