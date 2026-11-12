#!/usr/bin/env python3
"""Short list of the findings in CodeQL SARIF files (one line per finding).

  tools/sarif-summary.py <file.sarif|folder> ... [--markdown]

The CodeQL job keeps its SARIF files as the artifact "codeql-sarif-<language>",
so the findings can be read without access to Security -> Code scanning
(e.g. by the monthly audit: gh run download <run> -n codeql-sarif-python).
The SARIF lists every finding of the run, also ones dismissed on GitHub.
"""
import json
import os
import sys

SEV = {'error': 0, 'warning': 1, 'note': 2, 'none': 3}


def files(args):
    for a in args:
        if os.path.isdir(a):
            for root, _, names in os.walk(a):
                yield from (os.path.join(root, n) for n in sorted(names) if n.endswith('.sarif'))
        else:
            yield a


def findings(path):
    data = json.load(open(path, encoding='utf-8'))
    for run in data.get('runs', []):
        rules = {}
        for r in run.get('tool', {}).get('driver', {}).get('rules', []):
            rules[r.get('id')] = r
        for res in run.get('results', []):
            rid = res.get('ruleId', '?')
            rule = rules.get(rid, {})
            props = rule.get('properties', {})
            sev = props.get('problem.severity') or res.get('level') or rule.get('defaultConfiguration', {}).get('level', 'warning')
            sec = props.get('security-severity')
            loc = (res.get('locations') or [{}])[0].get('physicalLocation', {})
            f = loc.get('artifactLocation', {}).get('uri', '?')
            line = loc.get('region', {}).get('startLine', 0)
            msg = ' '.join(res.get('message', {}).get('text', '').split())
            yield (SEV.get(sev, 1), -(float(sec) if sec else 0), f, line, sev, sec, rid, msg)


def main():
    md = '--markdown' in sys.argv
    paths = [a for a in sys.argv[1:] if a != '--markdown']
    out = sorted(x for p in files(paths) for x in findings(p))
    if md:
        print(f'### CodeQL: {len(out)} finding(s)\n')
        if out:
            print('| Severity | Rule | Place | Message |\n|---|---|---|---|')
            for _, _, f, line, sev, sec, rid, msg in out:
                cell = msg.replace('|', '\\|')[:300]
                print(f"| {sev}{' ' + sec if sec else ''} | `{rid}` | `{f}:{line}` | {cell} |")
    else:
        for _, _, f, line, sev, sec, rid, msg in out:
            print(f"{sev}{'/' + sec if sec else ''}  {rid}  {f}:{line}  {msg[:300]}")
        print(f'{len(out)} finding(s)')


if __name__ == '__main__':
    main()
