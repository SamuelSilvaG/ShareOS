#!/usr/bin/env python3
"""Assemble the ShareOS website (GitHub Pages) into an output directory.

    python3 website/build.py [out]          (default: _site)

Copies the static pages from website/, the Markdown documents and their
images (docs/*.md, docs/images, README.md, CHANGELOG.md) for the wiki, and
writes data.json with a snapshot of releases, discussions, repository stats
and the app catalog. The pages ask the GitHub API live and fall back to this
snapshot (rate limit, offline). Network errors only leave parts of data.json
empty; the build never fails because of them.

GITHUB_TOKEN (set in Actions) raises the API rate limit.
"""
import json
import os
import shutil
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "UniqueDroid/ShareOS"
API = f"https://api.github.com/repos/{REPO}"
CATALOG = "https://github.com/UniqueDroid/ShareOS-Apps/releases/download/catalog/index.json"


def get(url):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "shareos-site-build"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
            return json.load(r)
    except Exception as e:  # noqa: BLE001 - any failure only empties a part of data.json
        print(f"warning: {url}: {e}", file=sys.stderr)
        return None


def releases():
    out = []
    for r in get(f"{API}/releases?per_page=10") or []:
        if r.get("draft"):
            continue
        out.append({
            "tag": r["tag_name"], "name": r.get("name") or r["tag_name"], "date": r.get("published_at"),
            "url": r["html_url"], "prerelease": r.get("prerelease", True), "body": r.get("body") or "",
            "assets": [{"name": a["name"], "size": a["size"], "url": a["browser_download_url"]} for a in r.get("assets", [])],
        })
    return out


def discussions():
    out = []
    for d in get(f"{API}/discussions?per_page=30") or []:
        out.append({
            "title": d["title"], "url": d["html_url"], "category": (d.get("category") or {}).get("name", ""),
            "author": (d.get("user") or {}).get("login", ""), "comments": d.get("comments", 0), "updated": d.get("updated_at"),
        })
    out.sort(key=lambda d: d["updated"] or "", reverse=True)
    return out


def apps():
    cat = get(CATALOG) or {}
    out = []
    for a in cat.get("apps", []):
        desc = a.get("description")
        if isinstance(desc, dict):
            desc = desc.get("en") or next(iter(desc.values()), "")
        vers = [v for v in a.get("versions", []) if not v.get("prerelease")] or a.get("versions", [])
        out.append({
            "id": a["id"], "name": a.get("name", a["id"]), "description": desc or "", "category": a.get("category", "other"),
            "icon": a.get("icon_url", ""), "type": a.get("type", "webapp"), "homepage": a.get("homepage") or f"https://github.com/UniqueDroid/ShareOS-Apps/tree/main/apps/{a['id']}",
            "version": vers[0]["version"] if vers else "",
        })
    return out


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "_site").resolve()
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(ROOT / "website", out, ignore=shutil.ignore_patterns("build.py", "__pycache__"))
    (out / "docs").mkdir(exist_ok=True)
    for md in (ROOT / "docs").glob("*.md"):
        shutil.copy2(md, out / "docs" / md.name)
    shutil.copytree(ROOT / "docs" / "images", out / "docs" / "images")
    for name in ("README.md", "CHANGELOG.md"):
        shutil.copy2(ROOT / name, out / name)
    (out / ".nojekyll").write_text("")

    repo = get(API) or {}
    data = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "repo": {"stars": repo.get("stargazers_count"), "forks": repo.get("forks_count")},
        "releases": releases(),
        "discussions": discussions(),
        "apps": apps(),
    }
    (out / "data.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(f"site in {out}: {len(data['releases'])} releases, {len(data['discussions'])} discussions, {len(data['apps'])} apps")


if __name__ == "__main__":
    main()
