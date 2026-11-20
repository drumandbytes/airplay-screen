# airplay-screen

Start and stop AirPlay screen sharing from the command line, even with the menu bar hidden.
Part of [Drumandbytes Projects](https://drumandbytes.com/projects/).

```sh
brew install --cask drumandbytes/tap/airplay-screen
```

macOS has no command for this, and the Screen Mirroring icon in Control Center can't be
scripted. `airplay-screen` drives System Settings → Displays instead: it opens it hidden,
presses the right menu entries and gets out of the way.

## Use

```sh
airplay-screen                # pick from a numbered list (picking the connected one disconnects)
airplay-screen list           # AirPlay displays on the network, one per line
airplay-screen start Telek    # connect (the Mac's screen is mirrored)
airplay-screen stop           # disconnect
airplay-screen status         # the connected display, or "not connected" and exit 1
airplay-screen permissions    # opens the Accessibility pane
```

`list` and `status` need no permission and open no windows. `start` and `stop` take 2–3 s.
If the receiver asks for a code, macOS shows its own prompt on your screen; `start` waits
up to 60 s for the connection.

Exit codes: 2 usage, 3 no Accessibility permission, 4 display not found, 5 the connection
didn't change, 6 `stop` with nothing connected.

## Permissions

`start` and `stop` press buttons in System Settings, which needs **Accessibility**
permission for the app you run the command from (Terminal, Ghostty, Hammerspoon, a launchd
job's parent...). Run `airplay-screen permissions`, then switch that app on. macOS grants
the permission to the app that started the command, not to `airplay-screen` itself.

## Known limits

- While it runs, System Settings has to be the active app (it only discovers AirPlay
  displays then), so keyboard focus moves for a second or two and the small "Mirror or
  extend to" menu flashes in the bottom-right corner. The Settings window itself is parked
  at the screen edge. The first run after login can show the window for ~35 ms.
- System Settings stays running, hidden, afterwards.
- Connecting always mirrors; mirror vs extend isn't selectable yet.
- Tested on macOS 27.2.1 against one TV. The menu structure is Apple's, so a macOS update
  can break it. The tests cover only the parsing helpers.

How it works, and the dead ends (private APIs, Shortcuts, existing tools):
[docs/internals.md](docs/internals.md).

## Build

```sh
swift build && swift test
scripts/build-app.sh [version]    # build/AirplayScreen.app, ad-hoc signed
```

MIT licence.
