#!/usr/bin/env python3
"""Draws docs/images/zeitstrahl.png: every commit as a dot on a time axis,
plus the milestones below. Run from the repository root:

    python3 scripts/zeitstrahl.py
"""
import datetime as dt
import subprocess
from zoneinfo import ZoneInfo

import matplotlib
matplotlib.use('Agg')
import matplotlib.dates as md
import matplotlib.pyplot as plt

TZ = ZoneInfo('Europe/Berlin')
OUT = 'docs/images/zeitstrahl.png'

# time (local), label, row (height), text alignment
MILESTONES = [
    ('2026-10-16 16:01', 'Alt-F importiert (Jan)', 0, 'left'),
    ('2026-10-16 17:10', 'neue Build-Basis', 1, 'center'),
    ('2026-10-16 19:10', 'Kernel < 3 MB', 2, 'center'),
    ('2026-10-16 21:25', 'UCI/ubus/rpcd\n+ Updater', 3, 'right'),
    ('2026-10-17 12:44', 'erster Start auf Hardware', 0, 'center'),
    ('2026-10-17 12:57', 'UBI-Layout', 1, 'center'),
    ('2026-10-17 14:11', 'Start aus Flash', 2, 'center'),
    ('2026-10-17 14:47', 'Weboberfläche + Updater', 0, 'center'),
    ('2026-10-17 15:44', 'uhttpd-Absturz behoben', 1, 'center'),
    ('2026-10-17 16:00', 'Speicher-Assistent', 3, 'right'),
]
# one panel per working session: start, end, hour tick interval, title
SESSIONS = [
    ('2026-10-16 15:40', '2026-10-16 22:10', 2, 'Fr 16.10.2026'),
    ('2026-10-17 11:15', '2026-10-17 16:30', 1, 'Sa 17.10.2026   (dazwischen Nacht)'),
]

BG, ACC, MUT, LINE, DIM, TXT, AMB = '#06090d', '#3da5ff', '#6f90ad', '#15253b', '#1d4f80', '#c6dff5', '#e6c25a'


def ts(s):
    return dt.datetime.strptime(s, '%Y-%m-%d %H:%M').replace(tzinfo=TZ)


def commits():
    out = subprocess.run(['git', 'log', '--reverse', '--format=%at|%an'], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        t, who = line.split('|', 1)
        yield dt.datetime.fromtimestamp(int(t), TZ), who


def main():
    cs = list(commits())
    claude = [t for t, w in cs if w == 'Claude']
    other = [t for t, w in cs if w != 'Claude']
    plt.rcParams.update({'font.family': 'DejaVu Sans Mono', 'text.color': TXT, 'xtick.color': MUT})
    widths = [(ts(b) - ts(a)).total_seconds() for a, b, _, _ in SESSIONS]
    fig, axes = plt.subplots(1, len(SESSIONS), figsize=(13, 4.8), gridspec_kw={'width_ratios': widths}, facecolor=BG)
    for ax, (a, b, step, title) in zip(axes, SESSIONS):
        a, b = ts(a), ts(b)
        ax.set_facecolor(BG)
        for s in ax.spines.values():
            s.set_color(LINE)
        ax.axhline(0, color=DIM, lw=1.5, zorder=1)
        c = [x for x in claude if a <= x <= b]
        o = [x for x in other if a <= x <= b]
        ax.scatter(c, [0] * len(c), s=46, color=ACC, zorder=3, edgecolors=BG, linewidths=1)
        ax.scatter(o, [0] * len(o), s=60, color=AMB, zorder=3, edgecolors=BG, linewidths=1)
        for when, label, row, ha in MILESTONES:
            x = ts(when)
            if a <= x <= b:
                y = 0.9 + row * 0.75
                ax.plot([x, x], [0.08, y - 0.08], color=DIM, lw=1, zorder=2)
                col = AMB if 'Jan' in label else ACC if ('Hardware' in label or 'Flash' in label) else TXT
                ax.text(x, y, label, ha=ha, va='bottom', fontsize=9, color=col)
        ax.set_xlim(a, b)
        ax.set_ylim(-0.6, 4.3)
        ax.set_yticks([])
        ax.xaxis.set_major_formatter(md.DateFormatter('%H:%M', tz=TZ))
        ax.xaxis.set_major_locator(md.HourLocator(interval=step, tz=TZ))
        ax.set_title(title, color=MUT, fontsize=10, loc='left')
    fig.suptitle('ShareOS – Entwicklungsverlauf in Commits', color=ACC, fontsize=13, x=0.02, ha='left', fontweight='bold')
    fig.text(0.02, 0.02, f'● blau: Commits von Claude ({len(claude)})   ● gelb: Jan ({len(other)}, Import von Alt-F)'
             '   ·   Jan: Idee, Entscheidungen, Tests an der Box', color=MUT, fontsize=9)
    plt.tight_layout(rect=(0, 0.05, 1, 0.93))
    plt.savefig(OUT, dpi=110, facecolor=BG)
    print(OUT, len(cs), 'commits')


if __name__ == '__main__':
    main()
