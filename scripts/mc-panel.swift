import AppKit
import Foundation
import WebKit

// Minimal menu-bar panel for Mission Control (ER-134 Phase B + stay-alive / one-click).
// Loads ~/.mission-control/panel.html (or argv override).
// Disables AppKit Automatic Termination — idle accessory apps otherwise exit silently.

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var webView: WKWebView!
  var timer: Timer?
  var hoverTimer: Timer?
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
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 560), configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    webView = web

    let pop = NSPopover()
    pop.contentSize = NSSize(width: 400, height: 560)
    pop.behavior = .transient
    pop.contentViewController = NSViewController()
    pop.contentViewController!.view = web
    popover = pop

    reload()
    updateStatusTitle()
    timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      self?.reload()
      self?.updateStatusTitle()
    }
  }

  // MARK: - Menu-bar title (live "needs you" count)

  // Reads the small local feed JSONs the collector already writes; never blocks.
  func needsSummary() -> (count: Int, redJobs: Int, ageSeconds: Int?) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var count = 0
    var redJobs = 0
    var newest: TimeInterval = 0

    func loadJSON(_ rel: String) -> [String: Any]? {
      let url = home.appendingPathComponent(rel)
      guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      if let e = obj["generated_epoch"] as? TimeInterval, e > newest { newest = e }
      return obj
    }

    var counted = false
    if let attn = loadJSON(".mission-control/data/attention.json"),
       (attn["ok"] as? Bool) == true,
       let d = attn["data"] as? [String: Any] {
      if let board = d["board"] as? [Any] { count = board.count; counted = true }
      else if let top = d["top5"] as? [Any] { count = top.count; counted = true }
    }
    if !counted,
       let dec = loadJSON(".mission-control/data/decisions.json"),
       let d = dec["data"] as? [String: Any],
       let pinned = d["pinned"] as? [Any] {
      count = pinned.count
    }
    if let auto = loadJSON(".mission-control/data/automation.json"),
       let d = auto["data"] as? [String: Any],
       let jobs = d["jobs"] as? [[String: Any]] {
      redJobs = jobs.filter { ($0["state"] as? String) == "red" }.count
    }
    let age = newest > 0 ? Int(Date().timeIntervalSince1970 - newest) : nil
    return (count, redJobs, age)
  }

  func updateStatusTitle() {
    guard let button = statusItem?.button else { return }
    let s = needsSummary()
    if s.count > 0 {
      button.attributedTitle = NSAttributedString(
        string: "MC \(s.count)", attributes: [.foregroundColor: NSColor.systemRed])
    } else if s.redJobs > 0 {
      button.attributedTitle = NSAttributedString(
        string: "MC !", attributes: [.foregroundColor: NSColor.systemOrange])
    } else {
      button.attributedTitle = NSAttributedString(
        string: "MC", attributes: [.foregroundColor: NSColor.labelColor])
    }
    var tip = "Mission Control"
    if s.count > 0 { tip += " — \(s.count) need\(s.count == 1 ? "s" : "") you" }
    else if s.redJobs > 0 { tip += " — \(s.redJobs) red job\(s.redJobs == 1 ? "" : "s")" }
    else { tip += " — all clear" }
    if let age = s.ageSeconds {
      if age < 60 { tip += " · updated \(age)s ago" }
      else if age < 3600 { tip += " · updated \(age / 60)m ago" }
      else { tip += " · updated \(age / 3600)h ago" }
    }
    button.toolTip = tip
  }

  // MARK: - Popover open/close

  @objc func togglePopover(_ sender: Any?) {
    hoverTimer?.invalidate()
    hoverTimer = nil
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      showPopover(over: button, activating: true)
    }
  }

  func showPopover(over button: NSStatusBarButton, activating: Bool) {
    guard !popover.isShown else { return }
    reload()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    if activating { NSApp.activate(ignoringOtherApps: true) }
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
