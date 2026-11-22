# airplay-screen

Start and stop **AirPlay screen mirroring** from the **macOS command line**: list the
receivers on your network, connect, disconnect, or pick one from a menu. It works with the
menu bar hidden and is easy to call from scripts.
Part of [Drumandbytes Projects](https://drumandbytes.com/projects/).

```sh
brew install --cask drumandbytes/tap/airplay-screen
```

It works with any AirPlay screen-mirroring target, not just TVs: Apple TV, AirPlay-capable
smart TVs, or another Mac (AirPlay Receiver). Handy for Hammerspoon, SketchyBar, launchd,
Raycast or Keyboard Maestro hooks.

macOS has no command for AirPlay mirroring, and the Screen Mirroring icon in Control Center
can't be scripted. `airplay-screen` drives System Settings → Displays instead: it opens it
hidden, presses the right menu entries and gets out of the way.

## Use

```sh
airplay-screen                    # pick from a numbered list (the connected one disconnects)
airplay-screen list               # AirPlay displays on the network, one per line
airplay-screen start "Living Room"  # connect (your screen is mirrored)
airplay-screen stop               # disconnect
airplay-screen status             # the connected display, or "not connected" and exit 1
airplay-screen permissions        # opens the Accessibility pane
```

`list` and `status` need no permission and open no windows. `start` and `stop` take 2–3 s.
If the receiver asks for a code, macOS shows its own prompt on your screen; `start` waits up
to 60 s for the connection.

Exit codes: 2 usage, 3 no Accessibility permission, 4 display not found, 5 the connection
didn't change, 6 `stop` with nothing connected, 7 no Local Network permission.

### In scripts

```sh
# toggle
if airplay-screen status >/dev/null; then airplay-screen stop; else airplay-screen start "Living Room"; fi
```

Anything that can run a command can call it. Run it as a separate process rather than
pressing System Settings yourself, since the menu blocks the caller while it is open.

From [Hammerspoon](https://www.hammerspoon.org/) (tested: `list`, `start` and `stop` from a
quick-settings menu):

```lua
hs.task.new("/opt/homebrew/bin/airplay-screen", function(code, out, err)
    if code ~= 0 then hs.alert.show(err) end
end, { "start", "Living Room" }):start()
```

Hammerspoon needs the Accessibility permission, and `airplay-screen` the Local Network one.

## Permissions

- **Local Network** (`list`, and the menu when you run it with no arguments): the first time
  `airplay-screen` looks for displays, macOS asks to allow it. Without it the search finds
  nothing and `list` exits with code 7.
- **Accessibility** (`start`, `stop`): the command presses buttons in System Settings, which
  needs the permission for the app you run it from (Terminal, Ghostty, Hammerspoon, a launchd
  job's parent...). Run `airplay-screen permissions`, then switch that app on. macOS grants it
  to the app that started the command, not to `airplay-screen` itself.

## Requirements

Apple Silicon, macOS 13 or later. Developed and tested on macOS 27.2.1 against a TV and other Macs; the
menu it drives is Apple's, so a macOS update can break it. Please
[open an issue](https://github.com/drumandbytes/airplay-screen/issues) with your macOS
version and what happened.

## Known limits

- While it runs, System Settings has to be the active app (it only discovers AirPlay
  displays then), so keyboard focus moves for a second or two and a small "Mirror or
  extend to" menu flashes in the bottom-right corner. The Settings window itself is parked
  at the screen edge. The first run after login can show the window for ~35 ms.
- System Settings stays running, hidden, afterwards.
- Connecting always mirrors; mirror vs extend isn't selectable yet.
- The tests cover only the parsing helpers: connecting needs a display and a receiver.

How it works, and the dead ends (private APIs, Shortcuts, existing tools):
[docs/internals.md](docs/internals.md).

## Build from source

```sh
swift build && swift test
scripts/build-app.sh [version]    # build/AirplayScreen.app, ad-hoc signed
```

The CLI is `build/AirplayScreen.app/Contents/MacOS/airplay-screen`.

## Licence

MIT.
