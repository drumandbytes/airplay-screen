# CLAUDE.md

## Project Overview

airplay-screen is a macOS CLI (Swift, SPM only, no Xcode project) that starts and stops AirPlay
screen sharing by driving System Settings → Displays through the Accessibility API. It ships
as an *app bundle* (`AirplayScreen.app`, executable `airplay-screen`) like the other
drumandbytes macOS tools; the cask links the executable into the PATH.

## Build & Test

```bash
swift build && swift test         # parsing helpers in Logic.swift are unit-tested
scripts/build-app.sh [version]    # build/AirplayScreen.app, ad-hoc signed
```

## Conventions

- **Commits**: Conventional Commits (`feat:`, `fix:`, `docs:`, `chore(deps):`); release-please reads them for the version bump and `CHANGELOG.md`.
- **Branches & PRs**: branch, PR, squash-merge. release-please's own bump PRs auto-merge on patch only.
- Command names, output and exit codes are a contract with consumers (Hammerspoon configs and shell scripts): change them only with a major version.

## Non-obvious pitfalls

Read `docs/internals.md` before touching the Settings handling: the focus, parking and hide/restore order is the product, and each step has a screen-recording-verified reason.

- `start`/`stop` can't be tested in CI (needs Accessibility, a display and a receiver); keep new logic in `Logic.swift` where it can be.
- Never send synthetic key events to close the menu (they hit the frontmost app); use `AXCancel`.
- `AXPress` on a menu button blocks until the menu closes; set a messaging timeout first.
- **Release flow**: tag push → `release.yml` builds, ad-hoc signs, zips, attaches to the release release-please created, then bumps `Casks/airplay-screen.rb` in `drumandbytes/homebrew-tap` as `dnb-robot`. The cask must already exist in the tap.
