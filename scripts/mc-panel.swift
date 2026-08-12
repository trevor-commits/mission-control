import AppKit
import Foundation
import WebKit

// Minimal menu-bar panel for Mission Control (ER-134 Phase B + stay-alive / one-click).
// Loads ~/.mission-control/panel.html (or argv override).
// Disables AppKit Automatic Termination — idle accessory apps otherwise exit silently.

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSWindowDelegate, NSPopoverDelegate {
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var webView: WKWebView!
  var timer: Timer?
  var hoverTimer: Timer?
  // AI Headroom: pinned always-on-top corner card + 15 s live data injection.
  var pinPanel: NSPanel?
  var pinWebView: WKWebView?
  var headroomTimer: Timer?
  // A transient popover races the status-item mouse-down that opens it. Keep
  // explicit monitors so the opening click survives and later outside clicks
  // still dismiss the panel.
  var popoverEventMonitors: [Any] = []
  // Retained RunningBoard activity — anonymous menu-bar binaries otherwise get
  // Control Center "after-life.interrupted" / workspace invalidation and exit.
  var stayAliveActivity: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    ProcessInfo.processInfo.disableAutomaticTermination("Mission Control menu bar")
    ProcessInfo.processInfo.disableSuddenTermination()
    stayAliveActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "Mission Control menu bar stay-alive")

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.title = "MC"
      button.toolTip = "Mission Control"
      button.action = #selector(togglePopover(_:))
      button.target = self
      // Hover preview: a short delay opens the popover without stealing focus.
      button.addTrackingArea(NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil))
    }
    statusItem = item

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "mcDecide")
    config.userContentController.add(self, name: "mcOpenFull")
    config.userContentController.add(self, name: "mcPin")
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 560), configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    webView = web

    let pop = NSPopover()
    pop.contentSize = NSSize(width: 400, height: 560)
    pop.behavior = .applicationDefined
    pop.delegate = self
    pop.contentViewController = NSViewController()
    pop.contentViewController!.view = web
    popover = pop

    reload()
    updateStatusTitle()
    timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      self?.reload()
      self?.updateStatusTitle()
    }
    // Live headroom: inject fresh collector data every 15 s (no page reloads).
    headroomTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.pushHeadroom()
      self?.updateStatusTitle()
    }
    let pinWanted = UserDefaults.standard.bool(forKey: "mcPinVisible")
    plog("launch pinWanted=\(pinWanted) bundle=\(Bundle.main.bundleIdentifier ?? "none")")
    if pinWanted {
      showPinPanel()
    }
  }

  // MARK: - AI Headroom (feed read, live injection, pinned corner card)

  // Plain file log: NSLog goes to the unified log where scripted reads are
  // unreliable; ops debugging needs a greppable file next to launchd's logs.
  func plog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/logs/mc-panel-debug.log")
    let stamp = ISO8601DateFormatter().string(from: Date())
    guard let data = "\(stamp) \(msg)\n".data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }

  func headroomFeedJSON() -> String? {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/data/headroom.json")
    guard let data = try? Data(contentsOf: url),
          let str = String(data: data, encoding: .utf8), !str.isEmpty else { return nil }
    return str
  }

  func finiteJSONNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite
    else { return nil }
    return number.doubleValue
  }

  func exactJSONInt(_ value: Any?) -> Int? {
    guard let number = finiteJSONNumber(value),
          number.rounded(.towardZero) == number,
          number >= Double(Int.min), number < Double(Int.max)
    else { return nil }
    return Int(number)
  }

  func exactJSONBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
  }

  func hasIncompleteMarker(_ value: [String: Any]) -> Bool {
    return exactJSONBool(value["partial"]) == true ||
      exactJSONBool(value["incomplete"]) == true ||
      exactJSONBool(value["complete"]) == false
  }

  func hasClearError(_ value: Any?) -> Bool {
    guard let value = value else { return true }
    if value is NSNull { return true }
    return (value as? String) == ""
  }

  func headroomLowest() -> (pct: Int, band: String)? {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/data/headroom.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          exactJSONInt(obj["schema"]) == 1,
          (obj["feed"] as? String) == "headroom",
          exactJSONBool(obj["ok"]) == true,
          obj.keys.contains("error"),
          hasClearError(obj["error"]),
          exactJSONInt(obj["cadence_s"]) == 60,
          let generatedEpoch = exactJSONInt(obj["generated_epoch"]), generatedEpoch > 0,
          !hasIncompleteMarker(obj),
          let feedData = obj["data"] as? [String: Any],
          !hasIncompleteMarker(feedData),
          let summary = feedData["summary"] as? [String: Any],
          let low = summary["lowest_quota"] as? [String: Any],
          let lowID = low["id"] as? String, !lowID.isEmpty,
          let rows = feedData["rows"] as? [[String: Any]]
    else { return nil }

    let matchingRows = rows.filter { ($0["id"] as? String) == lowID }
    let now = Date().timeIntervalSince1970
    let maxAge: TimeInterval = 300
    func isFresh(_ value: Any?) -> Bool {
      guard let epoch = finiteJSONNumber(value), epoch > 0 else { return false }
      let age = now - epoch
      return age >= 0 && age <= maxAge
    }

    func trustedQuota(_ candidate: [String: Any]) -> Double? {
      guard (candidate["kind"] as? String) == "quota",
            (candidate["health"] as? String) == "ok",
            (candidate["confidence"] as? String) == "live",
            let pct = finiteJSONNumber(candidate["remaining_pct"]),
            (0...100).contains(pct),
            isFresh(candidate["fetched_epoch"])
      else { return nil }
      if let rawAge = candidate["age_s"], !(rawAge is NSNull) {
        guard let age = finiteJSONNumber(rawAge), age >= 0, age <= maxAge else { return nil }
      }
      return pct
    }

    guard matchingRows.count == 1,
          let row = matchingRows.first,
          isFresh(generatedEpoch),
          let summaryPct = finiteJSONNumber(low["remaining_pct"]),
          let rowPct = trustedQuota(row),
          (0...100).contains(summaryPct),
          abs(summaryPct - rowPct) <= 0.01,
          let summaryBand = low["band"] as? String,
          let rowBand = row["band"] as? String,
          summaryBand == rowBand
    else { return nil }

    if rows.contains(where: { candidate in
      guard let candidatePct = trustedQuota(candidate) else { return false }
      return candidatePct < rowPct - 0.01
    }) { return nil }

    return (Int(rowPct.rounded()), rowBand)
  }

  func pushHeadroom() {
    guard let json = headroomFeedJSON() else { return }
    let js = "window.MC_updateHeadroom && window.MC_updateHeadroom(\(json));"
    webView?.evaluateJavaScript(js, completionHandler: nil)
    pinWebView?.evaluateJavaScript(js, completionHandler: nil)
  }

  func bandColor(_ band: String) -> NSColor {
    switch band {
    case "green": return .systemGreen
    case "yellow": return .systemYellow
    case "orange": return .systemOrange
    case "red": return .systemRed
    default: return .secondaryLabelColor
    }
  }

  func showPinPanel() {
    if let panel = pinPanel {
      panel.orderFrontRegardless()
      UserDefaults.standard.set(true, forKey: "mcPinVisible")
      return
    }
    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "mcDecide")
    config.userContentController.add(self, name: "mcOpenFull")
    config.userContentController.add(self, name: "mcPin")
    // Belt and suspenders: force pin mode even if the file URL query is dropped.
    config.userContentController.addUserScript(WKUserScript(
      source: "document.body.classList.add('pin');",
      injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 336, height: 460), configuration: config)
    pinWebView = web

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 336, height: 460),
      styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
      backing: .buffered, defer: false)
    panel.title = "AI Headroom"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.delegate = self
    panel.contentView = web

    if let saved = UserDefaults.standard.string(forKey: "mcPinFrame"), !saved.isEmpty {
      panel.setFrame(NSRectFromString(saved), display: false)
    } else if let screen = NSScreen.main ?? NSScreen.screens.first {
      let v = screen.visibleFrame
      panel.setFrameOrigin(NSPoint(x: v.maxX - 336 - 12, y: v.minY + 12))
    }
    loadPin(into: web)
    panel.orderFrontRegardless()
    pinPanel = panel
    UserDefaults.standard.set(true, forKey: "mcPinVisible")
    plog("pin panel shown frame=\(NSStringFromRect(panel.frame)) visible=\(panel.isVisible) screens=\(NSScreen.screens.map { NSStringFromRect($0.frame) })")
  }

  func loadPin(into web: WKWebView) {
    let args = CommandLine.arguments
    let override = args.count > 1 ? args[1] : nil
    let base = override.map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".mission-control/panel.html")
    guard FileManager.default.fileExists(atPath: base.path) else { return }
    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
    comps?.query = "mode=pin"
    let url = comps?.url ?? base
    web.loadFileURL(url, allowingReadAccessTo: base.deletingLastPathComponent())
  }

  func togglePinPanel() {
    if let panel = pinPanel, panel.isVisible {
      UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "mcPinFrame")
      panel.orderOut(nil)
      UserDefaults.standard.set(false, forKey: "mcPinVisible")
    } else {
      showPinPanel()
      pushHeadroom()
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === pinPanel {
      UserDefaults.standard.set(NSStringFromRect(sender.frame), forKey: "mcPinFrame")
      UserDefaults.standard.set(false, forKey: "mcPinVisible")
      sender.orderOut(nil)
      return false
    }
    return true
  }

  func windowDidMove(_ notification: Notification) {
    if let panel = notification.object as? NSPanel, panel === pinPanel {
      UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "mcPinFrame")
    }
  }

  // MARK: - Menu-bar title (live "needs you" count)

  // Reads the small local feed JSONs the collector already writes; never blocks.
  func needsSummary() -> (count: Int, redJobs: Int, ageSeconds: Int?, failedFeeds: [String]) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var count = 0
    var redJobs = 0
    var feedAges: [Int] = []
    var failedFeeds: [String] = []
    let now = Date().timeIntervalSince1970
    let expectedCadence = 300
    let knownAutomationStates: Set<String> = [
      "green", "yellow", "red", "degraded", "never", "retired",
      "offline-media", "awaiting-activation",
    ]

    func loadCoreFeed(_ name: String) -> (data: [String: Any], age: Int)? {
      let url = home.appendingPathComponent(".mission-control/data/\(name).json")
      guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            exactJSONInt(obj["schema"]) == 1,
            (obj["feed"] as? String) == name,
            exactJSONBool(obj["ok"]) == true,
            obj.keys.contains("error"),
            hasClearError(obj["error"]),
            exactJSONInt(obj["cadence_s"]) == expectedCadence,
            !hasIncompleteMarker(obj),
            let generatedEpoch = exactJSONInt(obj["generated_epoch"]), generatedEpoch > 0,
            let payload = obj["data"] as? [String: Any],
            !hasIncompleteMarker(payload)
      else { return nil }
      let rawAge = now - Double(generatedEpoch)
      guard rawAge >= 0, rawAge <= Double(expectedCadence * 3) else { return nil }

      if name == "attention" {
        guard let board = payload["board"] as? [[String: Any]],
              let top5 = payload["top5"] as? [[String: Any]],
              board.count >= top5.count
        else { return nil }
      } else if name == "decisions" {
        guard payload["pinned"] is [[String: Any]] else { return nil }
        if let syncValue = payload["sync"], !(syncValue is NSNull) {
          guard let sync = syncValue as? [String: Any],
                let dropped = finiteJSONNumber(sync["dropped"]), dropped >= 0
          else { return nil }
          if dropped > 0 { return nil }
        }
      } else if name == "automation" {
        guard let jobs = payload["jobs"] as? [[String: Any]],
              jobs.allSatisfy({ job in
                guard let state = job["state"] as? String else { return false }
                return knownAutomationStates.contains(state)
              })
        else { return nil }
        if let unregistered = payload["unregistered"] {
          if !(unregistered is NSNull) {
            guard let labels = unregistered as? [Any], labels.isEmpty else { return nil }
          }
        }
        if let note = payload["launchctl_note"],
           !(note is NSNull), !String(describing: note).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return nil
        }
      }
      return (payload, Int(rawAge))
    }

    let attention = loadCoreFeed("attention")
    let decisions = loadCoreFeed("decisions")
    let automation = loadCoreFeed("automation")
    for (name, state) in [("attention", attention), ("decisions", decisions), ("automation", automation)] {
      if let state = state { feedAges.append(state.age) }
      else { failedFeeds.append(name) }
    }

    if let board = attention?.data["board"] as? [[String: Any]], !board.isEmpty {
      count = board.count
    } else if let pinned = decisions?.data["pinned"] as? [[String: Any]] {
      count = pinned.count
    }
    if let jobs = automation?.data["jobs"] as? [[String: Any]] {
      redJobs = jobs.filter { ($0["state"] as? String) == "red" }.count
    }
    return (count, redJobs, feedAges.max(), failedFeeds)
  }

  func updateStatusTitle() {
    guard let button = statusItem?.button else { return }
    let s = needsSummary()
    let title = NSMutableAttributedString()
    if s.count > 0 {
      title.append(NSAttributedString(
        string: "MC \(s.count)", attributes: [.foregroundColor: NSColor.systemRed]))
    } else if s.redJobs > 0 || !s.failedFeeds.isEmpty {
      title.append(NSAttributedString(
        string: "MC !", attributes: [.foregroundColor: NSColor.systemOrange]))
    } else {
      title.append(NSAttributedString(
        string: "MC", attributes: [.foregroundColor: NSColor.labelColor]))
    }
    var lowTip = ""
    if let low = headroomLowest() {
      title.append(NSAttributedString(
        string: " ·\(low.pct)%",
        attributes: [.foregroundColor: bandColor(low.band)]))
      lowTip = " · lowest AI headroom \(low.pct)%"
    }
    button.attributedTitle = title
    var tip = "Mission Control"
    if s.count > 0 { tip += " — \(s.count) need\(s.count == 1 ? "s" : "") you" }
    else if s.redJobs > 0 { tip += " — \(s.redJobs) red job\(s.redJobs == 1 ? "" : "s")" }
    else if !s.failedFeeds.isEmpty { tip += " — feed data unavailable" }
    else { tip += " — all clear" }
    if !s.failedFeeds.isEmpty { tip += " · check \(s.failedFeeds.joined(separator: ", "))" }
    tip += lowTip
    if let age = s.ageSeconds {
      if age < 60 { tip += " · oldest core feed \(age)s ago" }
      else if age < 3600 { tip += " · oldest core feed \(age / 60)m ago" }
      else { tip += " · oldest core feed \(age / 3600)h ago" }
    }
    button.toolTip = tip
  }

  // MARK: - Popover open/close

  @objc func togglePopover(_ sender: Any?) {
    hoverTimer?.invalidate()
    hoverTimer = nil
    guard let button = statusItem.button else { return }
    if popover.isShown {
      closePopover()
    } else {
      showPopover(over: button, activating: true)
    }
  }

  func showPopover(over button: NSStatusBarButton, activating: Bool) {
    guard !popover.isShown else { return }
    reload()
    // Run after the status-item event completes. Showing synchronously lets the
    // opening mouse-down dismiss the popover before the matching mouse-up.
    DispatchQueue.main.async { [weak self, weak button] in
      guard let self = self, let button = button, !self.popover.isShown else { return }
      self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      if activating {
        self.popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
      }
      self.installPopoverDismissalMonitors()
    }
  }

  func closePopover() {
    removePopoverDismissalMonitors()
    if popover.isShown {
      popover.performClose(nil)
    }
  }

  func installPopoverDismissalMonitors() {
    removePopoverDismissalMonitors()
    let handler: (NSEvent) -> Void = { [weak self] event in
      guard let self = self, self.popover.isShown else { return }
      if let button = self.statusItem.button, let window = button.window {
        let location = window.mouseLocationOutsideOfEventStream
        if button.frame.contains(location) { return }
      }
      if let popoverWindow = self.popover.contentViewController?.view.window,
         event.window === popoverWindow {
        return
      }
      self.closePopover()
    }
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
      handler(event)
      return event
    }) {
      popoverEventMonitors.append(local)
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
      popoverEventMonitors.append(global)
    }
  }

  func removePopoverDismissalMonitors() {
    for monitor in popoverEventMonitors {
      NSEvent.removeMonitor(monitor)
    }
    popoverEventMonitors.removeAll()
  }

  func popoverDidClose(_ notification: Notification) {
    removePopoverDismissalMonitors()
  }

  // Hover opens a focus-safe preview after a short dwell; leaving the icon cancels.
  // (Plain methods, not overrides: AppDelegate is NSObject, and NSTrackingArea
  // delivers mouseEntered/mouseExited to its owner directly.)
  func mouseEntered(with event: NSEvent) {
    guard !popover.isShown else { return }
    hoverTimer?.invalidate()
    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
      guard let self = self, let button = self.statusItem?.button, !self.popover.isShown else { return }
      self.showPopover(over: button, activating: false)
    }
  }

  func mouseExited(with event: NSEvent) {
    hoverTimer?.invalidate()
    hoverTimer = nil
  }

  func reload() {
    let args = CommandLine.arguments
    let override = args.count > 1 ? args[1] : nil
    let home = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/panel.html")
    let url = override.map { URL(fileURLWithPath: $0) } ?? home
    if FileManager.default.fileExists(atPath: url.path) {
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
      let html = """
      <html><body style='font:13px -apple-system;padding:16px'>
      <h3>Mission Control panel not installed</h3>
      <p>Run: <code>dashboard install</code> then <code>dashboard panel</code>.</p>
      </body></html>
      """
      webView.loadHTMLString(html, baseURL: nil)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func openFullMissionControl() {
    let index = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/index.html")
    guard FileManager.default.fileExists(atPath: index.path) else {
      notify("Mission Control", "index.html missing — run dashboard install")
      return
    }
    NSWorkspace.shared.open(index)
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    if message.name == "mcPin" {
      DispatchQueue.main.async { [weak self] in self?.togglePinPanel() }
      return
    }
    if message.name == "mcOpenFull" {
      DispatchQueue.main.async { [weak self] in self?.openFullMissionControl() }
      return
    }
    guard message.name == "mcDecide" else { return }
    guard let body = message.body as? [String: Any] else { return }
    let idRaw = (body["id"] as? String) ?? ""
    let n: Int
    if let i = body["n"] as? Int {
      n = i
    } else if let s = body["n"] as? String, let i = Int(s) {
      n = i
    } else {
      return
    }
    guard n >= 1, n <= 9 else { return }
    guard idRaw.range(of: "^decision:[0-9a-f]{24}$", options: .regularExpression) != nil else { return }

    let home = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/bin/dashboard")
    let dash = home.path
    guard FileManager.default.isExecutableFile(atPath: dash) else {
      notify("Mission Control", "dashboard binary missing — run dashboard install")
      return
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: dash)
    proc.arguments = ["decide", "answer", idRaw, String(n)]
    proc.environment = ProcessInfo.processInfo.environment
    let err = Pipe()
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = err
    proc.terminationHandler = { [weak self] completed in
      let data = err.fileHandleForReading.readDataToEndOfFile()
      let msg = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "decide failed"
      DispatchQueue.main.async {
        guard let self = self else { return }
        if completed.terminationStatus == 0 {
          self.notify("Mission Control", "Recorded choice \(n)")
          self.reload()
        } else {
          self.notify("Mission Control", msg.isEmpty
            ? "decide answer failed (\(completed.terminationStatus))"
            : String(msg.prefix(180)))
        }
      }
    }
    do {
      try proc.run()
    } catch {
      notify("Mission Control", "Could not run decide answer")
    }
  }

  func notify(_ title: String, _ body: String) {
    let n = NSUserNotification()
    n.title = title
    n.informativeText = body
    NSUserNotificationCenter.default.deliver(n)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
ProcessInfo.processInfo.disableAutomaticTermination("Mission Control menu bar")
app.run()
