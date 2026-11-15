#!/usr/bin/env python3
"""Build manifest.json for JUJU Cinefex Reader from the cinefex-reader repo.

manifest = {
  "assets": [[url, path, size, crc], ...],       # every media file the reader can ask for
  "posters": {poster_path: video_url, ...},      # local-only video posters, generated from the clip
}
"""
import json, re, glob, sys, os, urllib.parse
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
# Reader view (Emmett, Nov 2026): each issue's reading.js names the iPad edition's article file
# (readingView*.html inside the issue ZIP) and a few extra images, with their sizes and CRCs.
def walk(node):
    if isinstance(node, dict):
        local = node.get('local')
        if isinstance(node.get('url'), str) and isinstance(local, dict) and {'path', 'size', 'crc'} <= local.keys():
            assets.setdefault(node['url'], local)            # {"url": …, "local": {name, path, size, crc}}
        for k, v in node.items():
            if isinstance(v, dict) and k.startswith('https://archive.org/download/') and {'path', 'size', 'crc'} <= v.keys():
                assets.setdefault(k, v)
            else:
                walk(v)
    elif isinstance(node, list):
        for v in node: walk(v)
for f in sorted(glob.glob(os.path.join(root, 'issues/*/reading.js'))):
    d = obj(open(f, encoding='utf-8').read(), 'CINEFEX_READING')
    walk(d)
    for art in d.get('articles', []):
        url = art.get('source')
        if url and art.get('sourceBytes') and url not in assets:
            name = urllib.parse.unquote(url).split('/')[-1]
            assets[url] = {'path': f"issues/{d['issue']}/assets/{name}", 'size': art['sourceBytes'], 'crc': art['sourceCrc']}
browse = next(p for p in (os.path.join(root, 'assets', 'data', 'browse-media.js'), os.path.join(root, 'browse-media.js')) if os.path.exists(p))
for u, a in obj(open(browse, encoding='utf-8').read(), 'BROWSE_SOURCES').items():
    assets.setdefault(u, a)
rows = [[u, a['path'], a['size'], a['crc']] for u, a in sorted(assets.items(), key=lambda x: x[1]['path'])]
posters = {p: v for p, v in posters.items() if f'local-media:{p}' in assets}
json.dump({'assets': rows, 'posters': posters}, open(out, 'w'), separators=(',', ':'))
ia = [r for r in rows if not r[0].startswith('local-media:')]
print(f"{len(rows)} assets ({len(ia)} from Internet Archive, {sum(r[2] for r in ia)/1e9:.1f} GB), {len(posters)} posters -> {out}")
