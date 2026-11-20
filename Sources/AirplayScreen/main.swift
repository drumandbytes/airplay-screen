// Drives System Settings → Displays → Add (+) → "Mirror or extend to" through the
// Accessibility API (the menu bar icon of Control Center isn't exposed to it).
// Needs Accessibility permission for the calling process; see README.md.
import AppKit
import ApplicationServices
import Network

let settingsID = "com.apple.systempreferences"

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v as AnyObject? : nil
}
func kids(_ el: AXUIElement) -> [AXUIElement] { (attr(el, "AXChildren") as? [AXUIElement]) ?? [] }
func role(_ el: AXUIElement) -> String { (attr(el, "AXRole") as? String) ?? "" }
func title(_ el: AXUIElement) -> String { (attr(el, "AXTitle") as? String) ?? "" }
func find(_ el: AXUIElement, _ depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if depth > 18 { return nil }
    if match(el) { return el }
    for k in kids(el) { if let f = find(k, depth + 1, match) { return f } }
    return nil
}
func fail(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

let previousApp = NSWorkspace.shared.frontmostApplication
var parked: [(AXUIElement, CGPoint)] = []

func settingsProcess() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).first
}

// Puts Settings back the way it was. Its windows go back to where they were while the
// app is hidden (so nothing flashes), which also keeps the parked spot out of the frame
// Settings saves on quit.
func closeSettings() {
    if let app = settingsProcess() {
        app.hide()
        Thread.sleep(forTimeInterval: 0.1)
        for (w, p) in parked where ProcessInfo.processInfo.environment["AIRPLAY_NORESTORE"] == nil {
            var p = p
            if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, "AXPosition" as CFString, v) }
        }
        // Settings stays running, hidden, with its window back at its normal spot: a fresh
        // launch draws the window for ~35 ms before the hide takes effect. Not closing the
        // window matters: a running Settings without one ignores a plain launch (Dock,
        // Spotlight, `open -b`), so opening it yourself would show nothing.
    }
    previousApp?.activate()
}

// Parks Settings' windows in the bottom-right corner (as AeroSpace hides windows); macOS
// clamps fully off-screen positions back, leaving a strip about 1x50 px. Done while the
// app is still hidden, so the window never shows at its normal spot.
func park(_ app: AXUIElement) {
    if ProcessInfo.processInfo.environment["AIRPLAY_NOPARK"] != nil { return }
    let corner = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    var p = CGPoint(x: corner.maxX - 1, y: corner.maxY - 1)
    guard let value = AXValueCreate(.cgPoint, &p) else { return }
    for w in (attr(app, "AXWindows") as? [AXUIElement]) ?? [] {
        if !parked.contains(where: { CFEqual($0.0, w) }), let v = attr(w, "AXPosition") {
            var old = CGPoint.zero
            AXValueGetValue(v as! AXValue, .cgPoint, &old)
            // an earlier run that got killed mid-way leaves the parked spot as Settings'
            // saved frame; put such a window back in the middle of the screen instead
            if old.x > corner.maxX - 100 || old.y > corner.maxY - 100, let main = NSScreen.main?.frame {
                var size = CGSize(width: 740, height: 625)
                if let sv = attr(w, "AXSize") { AXValueGetValue(sv as! AXValue, .cgSize, &size) }
                old = CGPoint(x: main.midX - size.width / 2, y: max(40, main.midY - size.height / 2))
            }
            parked.append((w, old))
        }
        AXUIElementSetAttributeValue(w, "AXPosition" as CFString, value)
    }
}

// Moving a window right after hide() doesn't always stick, so read it back.
func isParked(_ app: AXUIElement) -> Bool {
    let corner = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    return ((attr(app, "AXWindows") as? [AXUIElement]) ?? []).allSatisfy { w in
        var pos = CGPoint.zero
        guard let v = attr(w, "AXPosition") else { return false }
        AXValueGetValue(v as! AXValue, .cgPoint, &pos)
        return pos.x >= corner.maxX - 2
    }
}

func settingsApp() -> AXUIElement {
    guard AXIsProcessTrusted() else {
        fail("no Accessibility permission for this process.\nRun `airplay-screen permissions`, then enable the app you run this from (Terminal, Ghostty, Hammerspoon...).", 3)
    }
    if let running = settingsProcess(), !running.isHidden {
        running.hide()
        for _ in 0..<20 where !running.isHidden { Thread.sleep(forTimeInterval: 0.05) }
    }
    let sem = DispatchSemaphore(value: 0)
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = false
    cfg.hides = true // launch hidden; it's shown only once parked
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!,
                            configuration: cfg) { _, _ in sem.signal() }
    _ = sem.wait(timeout: .now() + 10)
    var proc: NSRunningApplication?
    var el: AXUIElement?
    for _ in 0..<100 { // a cold start of System Settings can take ~10 s
        proc = settingsProcess()
        if let proc {
            if !proc.isHidden { proc.hide() } // already running and visible: hide before moving
            el = AXUIElementCreateApplication(proc.processIdentifier)
            park(el!)
            if !parked.isEmpty && isParked(el!) { break }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if let proc, let el, !parked.isEmpty {
        // Settings only discovers AirPlay displays while it is the active app; a hidden
        // app's window contents aren't in the AX tree either
        proc.activate()
        for _ in 0..<50 {
            park(el) // unhiding can put a window back on screen
            if find(el, 0, { role($0) == "AXMenuButton" && title($0) == "Add" }) != nil { return el }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    closeSettings()
    fail("Displays pane didn't open")
}

// Opens the Add menu and returns it with the items under "Mirror or extend to".
// The menu's contents are fixed when it opens, and right after the pane loads
// AirPlay discovery hasn't finished, so reopen until the wanted device shows up.
// AXPress on a menu button doesn't return until the menu closes, so its wait is capped.
func mirrorItems(_ app: AXUIElement, want: String? = nil) -> (menu: AXUIElement?, items: [AXUIElement]) {
    let debug = ProcessInfo.processInfo.environment["AIRPLAY_DEBUG"] != nil
    var last: (AXUIElement?, [AXUIElement]) = (nil, [])
    for attempt in 0..<12 {
        if attempt > 0 {
            // cancelling the menu can hand focus back to the previous app, and the menu
            // neither opens nor discovers devices unless Settings is active
            settingsProcess()?.activate()
            Thread.sleep(forTimeInterval: 0.5)
        }
        // the button is rebuilt after its menu closes, so look it up again each time
        guard let plus = find(app, 0, { role($0) == "AXMenuButton" && title($0) == "Add" }) else { continue }
        let t0 = Date()
        AXUIElementSetMessagingTimeout(plus, 0.3)
        let pr = AXUIElementPerformAction(plus, "AXPress" as CFString)
        AXUIElementSetMessagingTimeout(plus, 3.0)
        if debug { FileHandle.standardError.write(String(format: "attempt %d press=%d took %.2fs active=%d\n", attempt, pr.rawValue, Date().timeIntervalSince(t0), settingsProcess()?.isActive == true ? 1 : 0).data(using: .utf8)!) }
        var menu: AXUIElement?
        for _ in 0..<20 {
            menu = find(plus, 0) { role($0) == "AXMenu" }
            if menu != nil { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard let menu else { continue }
        var items: [AXUIElement] = []
        var inSection = false
        for item in kids(menu) where role(item) == "AXMenuItem" {
            let t = title(item)
            if t == "Mirror or extend to" { inSection = true; continue }
            if inSection && (t.isEmpty || !((attr(item, "AXEnabled") as? Bool) ?? false)) { break } // separator
            if inSection { items.append(item) }
        }
        if debug {
            var pos = CGPoint.zero, size = CGSize.zero
            if let v = attr(menu, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &pos) }
            if let v = attr(menu, "AXSize") { AXValueGetValue(v as! AXValue, .cgSize, &size) }
            FileHandle.standardError.write("attempt \(attempt): menu at \(pos) size \(size) \(kids(menu).map(title))\n".data(using: .utf8)!)
        }
        last = (menu, items)
        let found = want.map { w in items.contains { title($0).localizedCaseInsensitiveCompare(w) == .orderedSame } } ?? !items.isEmpty
        if found { return last }
        _ = AXUIElementPerformAction(menu, "AXCancel" as CFString)
    }
    return last
}

// AirPlay receivers that accept screen mirroring. This Mac advertises itself too when
// AirPlay Receiver is on, so it's skipped.
func bonjourDisplays(wait: TimeInterval = 1.5) -> [String] {
    var names = Set<String>()
    let me = Host.current().localizedName ?? ""
    let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
    let lock = NSLock()
    browser.browseResultsChangedHandler = { results, _ in
        lock.lock(); defer { lock.unlock() }
        names = []
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint, name != me,
                  case let .bonjour(txt) = r.metadata,
                  supportsMirroring(features: txt["features"]) else { continue }
            names.insert(name)
        }
    }
    var browseError: NWError?
    browser.stateUpdateHandler = { state in
        lock.lock(); defer { lock.unlock() }
        if ProcessInfo.processInfo.environment["AIRPLAY_DEBUG"] != nil {
            FileHandle.standardError.write("browser state: \(state)\n".data(using: .utf8)!)
        }
        switch state {
        case .waiting(let e), .failed(let e): browseError = e
        default: break
        }
    }
    browser.start(queue: .global())
    Thread.sleep(forTimeInterval: wait)
    browser.cancel()
    lock.lock(); defer { lock.unlock() }
    if names.isEmpty, let browseError {
        fail("couldn't browse the network for AirPlay displays: \(browseError)\nThe app you run this from probably lacks Local Network permission (System Settings → Privacy & Security → Local Network).", 7)
    }
    return names.sorted()
}

func onlineDisplays() -> UInt32 {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    return n
}

func dump(_ el: AXUIElement, _ d: Int) {
    if d > 20 { return }
    let t = title(el), desc = (attr(el, "AXDescription") as? String) ?? ""
    let id = (attr(el, "AXIdentifier") as? String) ?? ""
    let val = attr(el, "AXValue").map { "\($0)" } ?? ""
    var actions: CFArray?
    AXUIElementCopyActionNames(el, &actions)
    let acts = (actions as? [String])?.joined(separator: ",") ?? ""
    print(String(repeating: "  ", count: d) + "\(role(el)) title=\"\(t)\" desc=\"\(desc)\" id=\"\(id)\" value=\"\(val.prefix(60))\" actions=\(acts)")
    for k in kids(el) { dump(k, d + 1) }
}

if ProcessInfo.processInfo.environment["AIRPLAY_TRACE"] != nil {
    let t0 = Date()
    Thread.detachNewThread {
        while true {
            if let p = settingsProcess() {
                let el = AXUIElementCreateApplication(p.processIdentifier)
                for w in (attr(el, "AXWindows") as? [AXUIElement]) ?? [] {
                    var pos = CGPoint.zero
                    if let v = attr(w, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &pos) }
                    FileHandle.standardError.write(String(format: "%.2fs hidden=%d active=%d pos=(%.0f,%.0f)\n",
                        Date().timeIntervalSince(t0), p.isHidden ? 1 : 0, p.isActive ? 1 : 0, pos.x, pos.y).data(using: .utf8)!)
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

func dumpPane() {
    let app = settingsApp()
    for w in (attr(app, "AXWindows") as? [AXUIElement]) ?? [] { dump(w, 0) }
    closeSettings()
}

func connectedDisplays() -> [String] {
    NSScreen.screens.compactMap { airPlayDisplayName($0.localizedName) }
}

func startDevice(_ name: String) {
    let app = settingsApp()
    let (menu, items) = mirrorItems(app, want: name)
    guard let item = items.first(where: { title($0).localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
        let found = items.map(title).joined(separator: ", ") // titles are gone once the menu closes
        if let menu { _ = AXUIElementPerformAction(menu, "AXCancel" as CFString) }
        closeSettings()
        fail("no AirPlay display named \"\(name)\"; found: \(found)", 4)
    }
    let before = onlineDisplays()
    let err = AXUIElementPerformAction(item, "AXPress" as CFString)
    if err != .success { closeSettings(); fail("couldn't press \"\(name)\" (AX error \(err.rawValue))") }
    // discovery needed Settings in front; the connection itself doesn't. Hide it before the
    // display change re-lays out windows (that pulls the parked one back on screen).
    settingsProcess()?.hide()
    previousApp?.activate()
    // Wait for the new display. A receiver set to "require code" makes macOS show its own
    // code prompt, so allow time to type it. Settings is kept until then: quitting it
    // early aborts the connection.
    var connected = false
    for _ in 0..<300 {
        if onlineDisplays() > before { connected = true; break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    closeSettings()
    if !connected { fail("pressed \"\(name)\" but no new display appeared within 60 s", 5) }
    print("connected to \(name)")
}

func stopDevice() {
    guard let name = connectedDisplays().first else { fail("no AirPlay display connected", 6) }
    // the connected device is ticked in the same menu start uses; choosing it again disconnects.
    // (The pane's Disconnect button needs the display selected first, and the display
    // thumbnails have no AX actions.)
    let app = settingsApp()
    let (menu, items) = mirrorItems(app, want: name)
    guard let item = items.first(where: { title($0).localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
        if let menu { _ = AXUIElementPerformAction(menu, "AXCancel" as CFString) }
        closeSettings()
        fail("\"\(name)\" isn't in the menu", 4)
    }
    let before = onlineDisplays()
    _ = AXUIElementPerformAction(item, "AXPress" as CFString)
    settingsProcess()?.hide()
    previousApp?.activate()
    for _ in 0..<50 where onlineDisplays() >= before { Thread.sleep(forTimeInterval: 0.1) }
    closeSettings()
    if onlineDisplays() >= before { fail("pressed \"\(name)\" but it's still connected", 5) }
    print("disconnected \(name)")
}

// Numbered list; picking the connected display disconnects it, any other one connects.
func pick() {
    let names = bonjourDisplays()
    if names.isEmpty { fail("no AirPlay displays found", 4) }
    let connected = connectedDisplays()
    for (i, n) in names.enumerated() { print("\(i + 1)) \(n)\(connected.contains(n) ? "   ✓ connected" : "")") }
    print("Number or name (empty to cancel): ", terminator: "")
    let input = readLine()
    guard let input, let name = resolveChoice(input, from: names) else {
        exit(input == nil ? 1 : 0) // EOF is an error; an empty or unknown answer just cancels
    }
    if connected.contains(name) { stopDevice() } else { startDevice(name) }
}

let usage = "usage: airplay-screen [list | start <name> | stop | status | permissions]"
let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil:
    guard isatty(0) != 0 else { fail(usage, 2) }
    pick()
case "list": bonjourDisplays().forEach { print($0) }
case "start":
    guard args.count == 2 else { fail("usage: airplay-screen start <name>", 2) }
    startDevice(args[1])
case "stop": stopDevice()
case "status":
    let names = connectedDisplays()
    if names.isEmpty { print("not connected"); exit(1) }
    names.forEach { print($0) }
case "permissions":
    print("Accessibility trusted for this process: \(AXIsProcessTrusted())")
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
case "dump": dumpPane() // debugging: prints the Displays pane's accessibility tree
default: fail(usage, 2)
}
