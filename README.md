# JUJU Cinefex Reader

A Mac app for reading the complete *Cinefex* archive: all 172 issues, 1980 to 2021.
It's built around [Emmett Redding's Cinefex Reader](https://github.com/holmesredding/cinefex-reader),
with his reader kept as he designed it. The app adds speed, an offline library and deeper indexing.

**[Download the latest version](https://github.com/mikeparsonstv-rgb/juju-cinefex-reader/releases/latest/download/JUJU-Cinefex-Reader.zip)**.
Unzip it and drag *JUJU Cinefex Reader* to Applications. It needs macOS 14 or later.
The app is signed and notarised by Apple, and it updates itself (*Check for Updates…* in the app menu).

## What it does
- **Reads straight away.** Pages load from Internet Archive as you read, and each one is kept on your Mac afterwards.
- **Optional full library.** The archive button (top right, beside ⓘ) can install all 56,403 files (14.6 GB) for offline reading.
  Pause and resume whenever you like. A ring on the button shows progress.
- **Search** across every word of every page.
- **Browse** films, TV and features, plus about 250 effects **companies** and 8,349 **ads** from 1,400 advertisers,
  with "Related" links between titles (Star Wars, Star Trek, the MCU, Harryhausen and more).
- **Reader view**: articles as resizable text with their photos and captions (Emmett's).
- **Save as PDF**, one issue at a time or the whole archive into a folder.

Shortcuts: ⌘1 Issues, ⌘2 Browse, ⌘[ and ⌘] Back and Forward, ⌘R Reload, ⇧⌘L Library, ⇧⌘I Install all issues.

## Versions
- **1.1** (24 November 2026): built on Emmett's reader at `8dd08e0e` (17 November): one search box for the whole catalogue with separate browsing filters, no blank flash between pages, page turns aligned while zoomed. The build tool now records the reader version in `READER_VERSION.txt`.
- **1.0** (15 November 2026): first version, built on Emmett's reader at `e25f5f21` (15 November) with the merged search and indexing and his Reader view.

## Credits
- Reader, page layouts and PDF export by **Emmett Redding**: [github.com/holmesredding/cinefex-reader](https://github.com/holmesredding/cinefex-reader)
- Magazine files from [Internet Archive](https://archive.org/details/cinefex-index). *Cinefex* © Cinefex.
- Mac app, search, companies and ads indexing by **JUJU VFX**

## Building from source
1. Get Emmett's reader and prepare it for the app:
   ```
   git clone https://github.com/holmesredding/cinefex-reader.git ../cinefex-reader
   python3 tools/prepare-reader.py ../cinefex-reader .
   ```
   This writes `Reader/` and `CinefexReader/manifest.json`. Run it again after pulling a new version of the reader.
2. Open `JUJU Cinefex Reader.xcodeproj` and Run. Xcode fetches [Sparkle](https://sparkle-project.org) for updates.

## Releasing (maintainer)
1. In Xcode, raise **Version** and **Build** on the target's General tab, then choose
   Product → Archive → Distribute App → **Direct Distribution**. Xcode signs, notarises and exports the app.
2. In Terminal, run `tools/publish.sh`, drag the exported app onto the window, add a line of release notes and press Return.
   The script zips the app, signs the update for Sparkle, writes `appcast.xml` and publishes the GitHub release.
   Installed copies pick it up within a day, or straight away through *Check for Updates…*.

The first time, `tools/publish.sh` only creates the update signing key, kept in your login keychain with a backup in Documents.
Archive and export once more so the app carries the key, then run it again.
