#!/usr/bin/env python3
"""Prepare Emmett's cinefex-reader for the JUJU Cinefex Reader Mac app.

usage: prepare-reader.py <cinefex-reader checkout> <app project folder>

Use the juju-index branch of github.com/mikeparsonstv-rgb/cinefex-reader (or Emmett's repo once he
merges it) to get Search, Companies, Ads and Related titles. Works with the assets/ + scripts/ layout
(Emmett's November 2026 update, with PDF export) and the older flat layout.

Writes:
  <app>/Reader/                      the reader, with every media URL pointed at the app
  <app>/CinefexReader/manifest.json  url -> library path, size, CRC (via make-manifest.py)

Re-run after pulling a new version of the reader.
"""
import os, re, shutil, sys, subprocess
src, app = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(app, 'Reader')
SKIP_DIRS = {'.git', '.github', '__pycache__', 'tools', 'scripts', 'docs'}   # build scripts and notes are not needed at runtime
SKIP_FILES = {'verify-package.py', 'VERIFICATION.json', '.gitignore', '.nojekyll'}
LEAVE_AS_IS = {'reader-info.js', 'README.md'}          # outbound links only
# App only: the real Cinefex masthead logo (from the issue 127 iPad edition) replaces the typed "cinefex"
# in the wordmark. It is used as a mask, so it takes the page's text colour in light and dark themes.
WORDMARK = re.compile(r'cinefex<span>READER</span>')
def juju_mark(prefix):
    return (f'<i role="img" aria-label="cinefex" style="display:block;width:2.9em;height:.82em;background:currentColor;'
            f'-webkit-mask:url({prefix}assets/cinefex-logo.png) left center/contain no-repeat;'
            f'mask:url({prefix}assets/cinefex-logo.png) left center/contain no-repeat"></i><span>READER</span>')
REWRITE = [('https://archive.org/download/', 'cinefex://reader/__ia/'),
           ('local-media:', 'cinefex://reader/__local/')]

# Files are overwritten in place (a connected folder may not allow deletes); stale files from an older reader stay.
files = rewritten = 0
for dirpath, dirs, names in os.walk(src):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    rel = os.path.relpath(dirpath, src)
    dest_dir = os.path.join(out, rel) if rel != '.' else out
    os.makedirs(dest_dir, exist_ok=True)
    for name in names:
        if name in SKIP_FILES: continue
        s, d = os.path.join(dirpath, name), os.path.join(dest_dir, name)
        files += 1
        if name == 'local-source.js' and rel in ('.', os.path.join('assets', 'js')):
            shutil.copyfile(os.path.join(here, 'juju-source.js'), d); continue
        if name.endswith(('.js', '.html', '.css')) and name not in LEAVE_AS_IS:
            text = open(s, encoding='utf-8').read(); new = text
            for a, b in REWRITE: new = new.replace(a, b)
            if name.endswith('.html'):
                prefix = '../' * (0 if rel == '.' else len(rel.split(os.sep)))
                new = WORDMARK.sub(juju_mark(prefix), new)
            open(d, 'w', encoding='utf-8').write(new)
            rewritten += new != text
        else:
            shutil.copyfile(s, d)
shutil.copyfile(os.path.join(here, 'cinefex-logo.png'), os.path.join(out, 'assets', 'cinefex-logo.png'))
print(f'Reader: {files} files, {rewritten} rewritten -> {out}')
subprocess.run([sys.executable, os.path.join(here, 'make-manifest.py'), src,
                os.path.join(app, 'CinefexReader', 'manifest.json')], check=True)
