#!/usr/bin/env python3
"""Language files: every file listed in languages.json exists, has the same
German keys and patterns as en.json, keeps the placeholders ($1 …) and all
regular expressions compile.

  tests/check-i18n.py
"""
import json
import re
import sys

D = 'src/shareos-core/www/i18n/'
ph = re.compile(r'\$\d')
errors = []
en = json.load(open(D + 'en.json', encoding='utf-8'))
langs = json.load(open(D + 'languages.json', encoding='utf-8'))
for l in langs:
    code = l['code']
    if code == 'de':
        continue
    try:
        j = json.load(open(D + code + '.json', encoding='utf-8'))
    except Exception as e:  # noqa: BLE001
        errors.append(f'{code}: {e}')
        continue
    if j.get('language') != code:
        errors.append(f'{code}: "language" is {j.get("language")!r}')
    missing = set(en['exact']) - set(j['exact'])
    if missing:
        errors.append(f'{code}: {len(missing)} texts missing, e.g. {sorted(missing)[:3]}')
    for k, v in j['exact'].items():
        if k in en['exact'] and sorted(ph.findall(v)) != sorted(ph.findall(en['exact'][k])):
            errors.append(f'{code}: placeholders differ in {k!r}')
    if [p[0] for p in j['patterns']] != [p[0] for p in en['patterns']]:
        errors.append(f'{code}: patterns differ from en.json (same order expected)')
    for (re_, rep), (_, en_rep) in zip(j['patterns'], en['patterns']):
        try:
            n = re.compile(re_).groups
        except re.error as e:
            errors.append(f'{code}: bad pattern {re_!r}: {e}')
            continue
        used = {int(x[1:]) for x in ph.findall(rep)}
        if used and max(used) > n:
            errors.append(f'{code}: {rep!r} uses a group that {re_!r} does not have')
        if sorted(ph.findall(rep)) != sorted(ph.findall(en_rep)):
            errors.append(f'{code}: placeholders differ in pattern {re_!r}')
    for w in j['words']:
        try:
            re.compile(w[0])
        except re.error as e:
            errors.append(f'{code}: bad word pattern {w[0]!r}: {e}')
print('\n'.join(errors) if errors else f'{len(langs)} languages OK')
sys.exit(1 if errors else 0)
