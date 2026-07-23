import AppKit
import Foundation
import WebKit

// Minimal menu-bar panel for Mission Control (ER-134 Phase B + stay-alive / one-click).
// Loads ~/.mission-control/panel.html (or argv override).
// Disables AppKit Automatic Termination — idle accessory apps otherwise exit silently.

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSPopoverDelegate {
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var webView: WKWebView!
  var timer: Timer?
  // Retained RunningBoard activity — anonymous menu-bar binaries otherwise get
  // Control Center "after-life.interrupted" / workspace invalidation and exit.
  var stayAliveActivity: NSObjectProtocol?
  // Transient NSPopover + NSStatusItem races the opening click (mouse-down closes
  // before mouse-up toggles). Drive dismissal ourselves instead.
  var popoverEventMonitors: [Any] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    ProcessInfo.processInfo.disableAutomaticTermination("Mission Control menu bar")
    ProcessInfo.processInfo.disableSuddenTermination()
    stayAliveActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "Mission Control menu bar stay-alive")

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.title = "MC"
      button.toolTip = "Mission Control — Needs you"
      button.action = #selector(togglePopover(_:))
      button.target = self
    }
    statusItem = item

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "mcDecide")
    config.userContentController.add(self, name: "mcOpenFull")
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 460), configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    webView = web

    let pop = NSPopover()
    pop.contentSize = NSSize(width: 380, height: 460)
    // applicationDefined: no auto-close on the status-item mouse-down that opens us.
    pop.behavior = .applicationDefined
    pop.delegate = self
    pop.contentViewController = NSViewController()
    pop.contentViewController!.view = web
    popover = pop

    reload()
    timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      self?.reload()
    }
  }

  @objc func togglePopover(_ sender: Any?) {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      closePopover()
      return
    }
    reload()
    // Defer past the status-item click so the opening mouse-down cannot dismiss us.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      self.popover.contentViewController?.view.window?.makeKey()
      NSApp.activate(ignoringOtherApps: true)
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
      // Clicks on the status button are handled by togglePopover.
      if let button = self.statusItem.button,
         let win = button.window {
        let loc = win.mouseLocationOutsideOfEventStream
        if button.frame.contains(loc) { return }
      }
      // Clicks inside the popover content should not dismiss.
      if let popWin = self.popover.contentViewController?.view.window,
         event.window === popWin {
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
