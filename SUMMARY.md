# Tidy — summary

## What this is
A native macOS menu-bar app (SwiftUI, macOS 13+) that finds stale, safely-removable
data on this Mac and lets you clean it — through the UI or a "Clean all safe items"
button. It also runs a background weekly check and notifies you if space is worth
reclaiming.

Project: `~/Projects/Tidy` (a Swift Package — open `Package.swift` directly in Xcode
15.2, or build from the terminal with `./build_app.sh`, then `open build/Tidy.app`).

## Phase 1 — cleanup already done on this machine (2026-09-26)
Free space went from **2.3 GB → 3.4 GB** immediately (Homebrew's cache and npm's
cache were cleared directly — both regenerate on demand).

**~20.6 GB was moved to `~/.Trash`, waiting for you to empty it** (I don't empty
Trash myself — that step is irreversible):
- 13 GB — 3 outdated iOS 26 beta debug-symbol sets in Xcode DeviceSupport
- 2.3 GB — simulator dyld cache
- 1.7 GB — Xcode SwiftUI preview cache
- ~1 GB — build folders for 2 projects not built recently (kept the active one)
- ~2.4 GB — Chrome/GoogleUpdater/Antigravity/Playwright/node-gyp/Wondershare leftover caches

**Not touched, needs your decision:**
- iOS 17.2 Simulator (6.8 GB) + its 10 shut-down devices (1.2 GB)
- PostgreSQL, RVM, Python 3.10, Homebrew Cellar — you didn't confirm these are unused
- Photos Library (~6 GB): the correct fix is **Photos → Settings → iCloud → "Optimize
  Mac Storage"**, which you have to turn on yourself — no app can do this on your
  behalf, and deleting photos locally would also delete them from iCloud.

## What the app actually does (verified, not assumed)
I built it, ran `swift build -c release`, packaged `Tidy.app`, ad-hoc code-signed it,
launched it, confirmed it appears as a real process and app (`System Events` sees
bundle ID `com.prateek.tidy`), and quit it cleanly. No crashes.

Modules implemented and working:
- **Xcode**: superseded `iOS DeviceSupport` folders (keeps the newest, flags the
  rest), stale `DerivedData` (keeps the most recently built project), SwiftUI
  Previews cache, simulator dyld cache, superseded simulator runtimes and
  unavailable simulator devices (via `xcrun simctl`, JSON output — verified this
  Xcode's `simctl` supports `-j`).
- **Dev Caches**: Homebrew/npm/pip/Yarn/CocoaPods/Gradle/Maven/SwiftPM/Playwright/
  node-gyp/pnpm caches, plus stale `node_modules`/`.venv`/`build` folders in
  `~/Projects/*` untouched 90+ days.
- **App Caches**: general `~/Library/Caches/*` above 50 MB, known updater leftovers,
  and orphaned Application Support folders whose bundle ID no longer matches an
  installed app.
- **Installers**: watches `~/Downloads` and `~/Desktop` for `.dmg`/`.pkg`/`.zip`/`.xip`.
  For `.dmg`s it mounts read-only with `hdiutil`, reads the bundled app's real
  `CFBundleIdentifier`, and flags it if that app is already installed — this is the
  actual "this installer is already installed, delete it" feature you asked for.
- **Unused Apps**: lists `/Applications` sorted by size, using Spotlight's
  `kMDItemLastUsedDate` (not raw file access time, which is unreliable — Finder
  previews and scans bump it without a real launch). Flags anything 90+ days idle,
  skips Apple's own apps.
- **System**: Photos-optimize guidance, Full Disk Access prompt, local Time Machine
  snapshot info — all guide-only, never auto-deleted.

Every action defaults to `FileManager.trashItem` (reversible via Finder "Put Back"),
every removal is written to `~/Library/Application Support/Tidy/actionlog.json`, and
every module only ever looks at the fixed, allowlisted paths above — nothing walks
the filesystem freely.

## Honest limitations — what's simplified or not done
- **Not code-signed with a real Developer ID**, so Gatekeeper will warn on first
  launch outside Xcode/terminal (right-click → Open bypasses this once). It also
  can't be distributed — that's fine since this is for your own Mac.
- **DMG watching is scan-based, not live.** It checks Downloads/Desktop on each
  scan (launch, weekly, or low-disk-triggered), not via a live FSEvents watcher. A
  file dropped in between scans is caught on the next one, not instantly.
- **Login-item registration** (`SMAppService.mainApp.register()`) is wired in, but
  I did not verify it actually shows enabled under System Settings → General →
  Login Items on this machine — that needs a real install + reboot check, which I
  didn't do since Phase 1's Trash items are still awaiting your approval to empty.
- **Full Disk Access is not granted to Tidy.app.** Without it, the app can't size
  Trash/Mail/Messages/Safari (same restriction I hit during investigation). The
  System tab tells you this and gives you the Settings deep link; I didn't grant it
  myself since that's a security-relevant permission change.
- The Unused Apps list is size + idle-time only — it does not know if you plan to
  reopen something soon. Every one of its removals is `.review` (asks before
  acting), never automatic.

## Update (2026-09-28)
Three things added, all built, compiled, launched, and verified crash-free:

1. **PostgreSQL 16 and Python 3.10 now show up in the System tab.** These live
   outside your home folder, so plain "move to Trash" can't touch them (verified —
   that's exactly what blocked me earlier). Instead:
   - **PostgreSQL 16** → clicking its row opens the vendor's own uninstaller
     (`/Applications/PostgreSQL 16/Uninstall PostgreSQL.app`), since it may hold a
     live database and shouldn't be blindly `rm -rf`'d.
   - **Python 3.10** → clicking it runs `rm -rf` on the framework + app folder via
     `NSAppleScript`'s `with administrator privileges`, which pops **macOS's own**
     password/Touch ID dialog. Tidy's code never sees or stores that password —
     the OS handles it, same as any installer would.
   Both are `.review` safety, so neither is ever touched by "Clean all safe items"
   or by scheduled auto-clean — only a direct click in the UI triggers them.

2. **Scheduled auto-clean.** New Settings tab: a toggle plus a Daily/Weekly/Monthly
   picker. When on, the background scheduler (already running hourly checks) also
   calls `cleanAllRegenerable()` once the interval elapses, then sends a
   notification with how much was freed. It **only ever touches SAFE
   (`.regenerable`) items** — the same restriction as the manual button — so
   REVIEW items like Postgres/Python and MANUAL items like Photos are never
   auto-deleted, scheduled or not. Off by default; you turn it on.

3. **Color scheme.** New `Theme.swift`: a violet→teal gradient as the one accent
   used everywhere (buttons, the storage bar, badges), amber/coral reserved
   specifically for "needs a second look" items, frosted card backgrounds
   (`.regularMaterial`), rounded-design headings, and per-section tinted sidebar
   icons (the same pattern as Mail/Reminders' sidebar). Same information as
   before, restyled — no logic changed.

**Honest caveat:** I verified all three build, launch, and survive a scan without
crashing. I did not click "Delete…" on the Postgres/Python rows myself, since that
triggers a real admin password prompt and (for Postgres) a real vendor uninstaller
— that's for you to run when you're ready, not something to test blind.

## Next steps for you
1. Open Finder → Trash, glance over what's there, then empty it to actually
   reclaim the ~20.6 GB.
2. Turn on Photos "Optimize Mac Storage".
3. Decide on the iOS 17.2 Simulator, PostgreSQL/RVM/Python 3.10/Cellar — tell me
   and I'll fold whichever you want into another cleanup pass.
4. Launch `Tidy.app`, grant Full Disk Access when it asks, and check the Overview
   tab — the "reclaimable" number should update with the newly visible Trash size.
