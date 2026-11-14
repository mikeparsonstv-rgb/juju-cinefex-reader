#!/usr/bin/env python3
"""Build manifest.json for JUJU Cinefex Reader from the cinefex-reader repo.

manifest = {
  "assets": [[url, path, size, crc], ...],       # every media file the reader can ask for
  "posters": {poster_path: video_url, ...},      # local-only video posters, generated from the clip
}
"""
import json, re, glob, sys, os
root = sys.argv[1]; out = sys.argv[2]
assets = {}; posters = {}
def obj(text, var):
    return json.loads(re.search(r'window\.' + var + r'=(\{.*?\})\s*;?\s*$', text, re.S).group(1))
for f in sorted(glob.glob(os.path.join(root, 'issues/*/data.js'))):
    d = obj(open(f, encoding='utf-8').read(), 'ISSUE')
    for u, a in (d.get('localAssets') or {}).items():
        assets[u] = a
    for key, src in (d.get('mediaSources') or {}).items():
        if not key.startswith('assets/videos/'): continue
        name = key.split('/')[-1]
        posters[f"issues/{d['issue']}/assets/posters/{name}.jpg"] = src['url']
browse = next(p for p in (os.path.join(root, 'assets', 'data', 'browse-media.js'), os.path.join(root, 'browse-media.js')) if os.path.exists(p))
for u, a in obj(open(browse, encoding='utf-8').read(), 'BROWSE_SOURCES').items():
    assets.setdefault(u, a)
rows = [[u, a['path'], a['size'], a['crc']] for u, a in sorted(assets.items(), key=lambda x: x[1]['path'])]
posters = {p: v for p, v in posters.items() if f'local-media:{p}' in assets}
json.dump({'assets': rows, 'posters': posters}, open(out, 'w'), separators=(',', ':'))
ia = [r for r in rows if not r[0].startswith('local-media:')]
print(f"{len(rows)} assets ({len(ia)} from Internet Archive, {sum(r[2] for r in ia)/1e9:.1f} GB), {len(posters)} posters -> {out}")
