#!/usr/bin/env python3
"""JUJU Cinefex Reader - bulk archive installer.

Downloads every media file the Cinefex Reader uses from Internet Archive into
    <library>/media/<path>
checking each file's size and CRC-32 against the manifest. Files that are
damaged on Internet Archive (issues 11-16) are taken from the reader's repair ZIP.
Safe to stop and re-run: finished files are skipped.

usage: cinefex-download.py <manifest.json> <library folder> [workers]
"""
import json, os, sys, time, zlib, zipfile, threading, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

REPAIR_URL = ('https://archive.org/download/cinefex-reader-repairs-011-016/'
              'Cinefex%20Reader%20Repairs%20011-016.zip')
UA = 'JUJU-Cinefex-Reader/1.0 (personal archive mirror)'

manifest_path, library = sys.argv[1], sys.argv[2]
workers = int(sys.argv[3]) if len(sys.argv) > 3 else 8
media = os.path.join(library, 'media')
os.makedirs(media, exist_ok=True)
assets = [a for a in json.load(open(manifest_path))['assets'] if not a[0].startswith('local-media:')]
lock = threading.Lock()
stats = dict(total=len(assets), bytesTotal=sum(a[2] for a in assets), done=0, bytesDone=0,
             skipped=0, downloaded=0, repaired=0, failed=0, started=time.time(), state='running')
failures = []
log = open(os.path.join(library, 'install-log.txt'), 'a', buffering=1)

def say(msg):
    log.write(time.strftime('%Y-%m-%d %H:%M:%S ') + msg + '\n')

def write_status(final=False):
    s = dict(stats)
    if final: s['state'] = 'finished' if not stats['failed'] else 'finished-with-failures'
    s['updated'] = time.time()
    tmp = os.path.join(library, '.install-status.json.tmp')
    with open(tmp, 'w') as f: json.dump(s, f)
    os.replace(tmp, os.path.join(library, 'install-status.json'))

def crc_of(path):
    c = 0
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''): c = zlib.crc32(chunk, c)
    return c & 0xffffffff

def fetch(url, dest, size, crc, attempts=6):
    tmp = dest + '.part'
    for n in range(attempts):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, 'wb') as f:
                c = 0
                for chunk in iter(lambda: r.read(1 << 18), b''):
                    f.write(chunk); c = zlib.crc32(chunk, c)
            got = os.path.getsize(tmp)
            if got == size and (c & 0xffffffff) == crc:
                os.replace(tmp, dest); return 'ok'
            return 'mismatch'          # Internet Archive copy differs - leave for the repair pass
        except urllib.error.HTTPError as e:
            if e.code == 404: return 'missing'
            time.sleep(min(60, 3 * 2 ** n))
        except Exception:
            time.sleep(min(60, 3 * 2 ** n))
    return 'error'

def job(a):
    url, path, size, crc = a
    dest = os.path.join(media, path)
    if os.path.exists(dest) and os.path.getsize(dest) == size:
        return a, 'skip'
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    return a, fetch(url, dest, size, crc)

def repair_pass(wanted):
    """Fill files from the repair ZIP, matched by size + CRC (that is how the web reader matches them)."""
    if not wanted: return 0
    zpath = os.path.join(library, 'Cinefex Reader Repairs 011-016.zip')
    if not os.path.exists(zpath):
        say('Downloading repair ZIP for issues 11-16')
        req = urllib.request.Request(REPAIR_URL, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=300) as r, open(zpath + '.part', 'wb') as f:
            for chunk in iter(lambda: r.read(1 << 20), b''): f.write(chunk)
        os.replace(zpath + '.part', zpath)
    by_key = {(a[2], a[3]): a for a in wanted}
    fixed = 0
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            a = by_key.get((info.file_size, info.CRC))
            if not a: continue
            dest = os.path.join(media, a[1]); os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest + '.part', 'wb') as out:
                for chunk in iter(lambda: src.read(1 << 20), b''): out.write(chunk)
            os.replace(dest + '.part', dest); fixed += 1
    return fixed

say(f'Start: {stats["total"]} files, {stats["bytesTotal"]/1e9:.1f} GB, {workers} workers')
write_status()
last = 0
retry = []
with ThreadPoolExecutor(workers) as pool:
    for fut in as_completed([pool.submit(job, a) for a in assets]):
        a, result = fut.result()
        with lock:
            stats['done'] += 1
            if result in ('ok', 'skip'):
                stats['bytesDone'] += a[2]
                stats['skipped' if result == 'skip' else 'downloaded'] += 1
            else:
                retry.append(a); failures.append([a[1], result])
            if time.time() - last > 2: write_status(); last = time.time()

if retry:
    say(f'{len(retry)} files need the repair ZIP or a retry')
    try:
        n = repair_pass(retry); stats['repaired'] = n; say(f'Repaired {n} files from the repair ZIP')
    except Exception as e:
        say(f'Repair pass failed: {e}')
    still = [a for a in retry if not (os.path.exists(os.path.join(media, a[1])) and os.path.getsize(os.path.join(media, a[1])) == a[2])]
    stats['bytesDone'] += sum(a[2] for a in retry if a not in still)
    stats['failed'] = len(still)
    with open(os.path.join(library, 'install-failures.txt'), 'w') as f:
        for a in still: f.write(f'{a[1]}\t{a[0]}\n')
write_status(final=True)
say(f'Finished: {stats["downloaded"]} downloaded, {stats["skipped"]} already present, '
    f'{stats["repaired"]} repaired, {stats["failed"]} failed')
