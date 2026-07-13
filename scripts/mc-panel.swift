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

  func applicationDidFinishLaunching(_ notification: Notification) {
    ProcessInfo.processInfo.disableAutomaticTermination("Mission Control menu bar")
    ProcessInfo.processInfo.disableSuddenTermination()

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
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 460), configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    webView = web

    let pop = NSPopover()
    pop.contentSize = NSSize(width: 380, height: 460)
    pop.behavior = .transient
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
      popover.performClose(sender)
    } else {
      reload()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApp.activate(ignoringOtherApps: true)
    }
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

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
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
    // Allow decision ids like decision:uuid or plain tokens — no shell metacharacters.
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":_-."))
    guard !idRaw.isEmpty, idRaw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return }

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
    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    do {
      try proc.run()
      proc.waitUntilExit()
      if proc.terminationStatus == 0 {
        notify("Mission Control", "Recorded choice \(n)")
        DispatchQueue.main.async { [weak self] in self?.reload() }
      } else {
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "decide failed"
        notify("Mission Control", msg.isEmpty ? "decide answer failed (\(proc.terminationStatus))" : String(msg.prefix(180)))
      }
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
