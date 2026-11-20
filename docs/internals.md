# How airplay-screen works

Internals, gotchas and dead ends, for whoever touches the code next. Usage is in the
[README](../README.md). Findings are from macOS 27.2.1 on Apple Silicon.

## How it works

`start` opens System Settings → Displays, moves its window to the bottom-right corner
with 1 px on screen (the way AeroSpace hides windows; fully off-screen positions get
clamped back), presses **Add (+)** through the Accessibility API, and presses the device
under **"Mirror or extend to"**. It then hands focus back to the previous app, waits for
the new display (`CGGetOnlineDisplayList`), moves the window back to its normal spot while
hidden, and leaves Settings running, hidden, window and all. A fresh launch draws its window
for ~35 ms (seen in a 120 fps screen recording) before the hide takes effect; a hidden
Settings is parked before it's shown, so only the first run after login can flash. The
window stays open on purpose: a running Settings without a window ignores a plain launch
(Dock, Spotlight, `open -b`), so opening it yourself would show nothing. With the window
kept, opening Settings yourself shows it at its normal spot (on the Displays pane).

`stop` opens the same menu: the connected device is ticked (✓) under "Mirror or extend
to", and choosing it again disconnects. (The pane's Disconnect button only shows with the
AirPlay display selected, and the display thumbnails have no AX actions, so it can't be
selected without a real click.)

`list` doesn't touch the UI: it browses `_airplay._tcp` over Bonjour and keeps receivers
whose TXT `features` has bit 7 (screen mirroring), skipping this Mac. It can show a TV in
standby (cached record); `start` only sees it once it's actually reachable.

## Gotchas found the hard way

- **Settings must be the active app.** It only discovers AirPlay displays while in front;
  opened in the background, "Mirror or extend to" never appears. Parking the window keeps
  this invisible, but keyboard focus moves to Settings for a second or two.
- **The menu's contents are fixed when it opens.** Right after the pane loads, discovery
  may not be done, so `start` cancels and reopens the menu every 0.5 s (up to ~6 s).
- **Don't quit Settings right after pressing the device.** Quitting 1 s later aborted the
  connection ("Couldn't connect to Telek"). `start` waits for the display to appear.
- **`AXPress` on a menu button blocks until the menu closes.** Set
  `AXUIElementSetMessagingTimeout` before pressing. Without it the caller hangs:
  Hammerspoon's `hs.axuielement` froze its main thread (all hotkeys) until Settings quit.
- Close menus with `AXCancel` on the `AXMenu`, never a synthetic Escape: a key event goes
  to whatever app is frontmost.
- Another app's window can't be put behind other windows (no AX attribute for window
  level). Instead Settings is launched hidden (`OpenConfiguration.hides`), its window is
  parked while hidden, and only then is it activated, so it never shows at its normal
  spot. macOS clamps the parked window to a ~1x50 px strip at the bottom-right edge.
- Moving a window right after `hide()` doesn't always stick (seen with Settings already
  running): `settingsApp` reads the position back and only activates once it's parked.
  Debug switches: `AIRPLAY_TRACE=1` logs the window position every 50 ms, `AIRPLAY_DEBUG=1` the menu attempts, `AIRPLAY_NOPARK=1` and `AIRPLAY_NORESTORE=1` turn off parking and the position restore.
- A hidden app's window contents aren't in the AX tree: the window can be moved while
  hidden, but the Add button only shows up after activating.
- Settings saves its window frame on quit, so quitting it while parked makes the next
  manual open land in the corner. `closeSettings` hides it, moves the window back (to the
  screen centre if the old spot was the parked one) and leaves it hidden. After the fix a fresh
  launch opened at the bottom-right but fully on screen: the restore while hidden may not
  be fully honoured. Not chased further.

## Ruled out

- **Control Center / menu bar icon via Accessibility**: `AXExtrasMenuBar` of ControlCenter
  and SystemUIServer has no children for any client (System Events, Swift, Hammerspoon),
  even with the hidden menu bar revealed. `AXManualAccessibility` /
  `AXEnhancedUserInterface` can't be set (-25205 / -25208).
- **Private AVFoundation routing API** :
  `AVOutputContext` (`+sharedSystemScreenContext`, `-setOutputDevice:options:...`) and
  `AVOutputDeviceDiscoverySession` exist, but from our binary the context is nil and
  discovery returns nothing. Control Center and AirPlayUIAgent hold restricted Apple
  entitlements for it (`com.apple.avfoundation.allow-system-wide-context`,
  `allows-access-to-device-list`, `allows-set-output-device`); a third-party binary only
  gets them with SIP + AMFI disabled.
- **Shortcuts / App Intents**: only receiver-side AirPlay intents exist.
- **Open-source senders**: none found (UxPlay etc. are receivers; pyatv streams audio and
  files, no mirroring). A protocol-level sender would be a weeks-long reverse-engineering job.

## Ideas not built

1. Mirror vs extend: the pane shows a "Use as" popup (value "Main display") and a mirror
   popup (value "<name>") after connecting; an `--extend` flag could set them.
2. A menu bar helper app that holds the Accessibility permission itself, so launchd jobs
   and Shortcuts don't depend on their parent app's grant (the CLI would talk to it). Today
   the grant belongs to the app that started the command (Terminal, Hammerspoon...).
3. A stable code-signing identity, so a grant to the app bundle survives updates
   (ad-hoc signatures change on every build).
