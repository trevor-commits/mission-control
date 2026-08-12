#!/usr/bin/env swift
import AppKit
import Foundation
import WebKit

private func jsonLiteral(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: []),
          let text = String(data: data, encoding: .utf8) else {
        return "null"
    }
    return text
}

private func runProcess(_ executable: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } catch {
        return (127, "\(error.localizedDescription)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var web: WKWebView!
    private var timer: Timer?
    private var lastHealth: [String: Any]?
    private var healthRefreshInFlight = false

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private var mcHome: String { ProcessInfo.processInfo.environment["MISSION_CONTROL_HOME"] ?? "\(home)/.mission-control" }
    private var healthBin: String { ProcessInfo.processInfo.environment["MISSION_CONTROL_RESOURCE_HEALTH_BIN"] ?? "\(mcHome)/bin/resource-health" }
    private var governorBin: String { ProcessInfo.processInfo.environment["MISSION_CONTROL_GOVERNOR_BIN"] ?? "\(home)/.local/bin/governor" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp])
        applyMenuState(nil)

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        ["mcOpenDashboard", "mcDecision", "mcReload", "mcOptimize"].forEach {
            config.userContentController.add(self, name: $0)
        }
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 620), configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")

        let controller = NSViewController()
        controller.view = web
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.behavior = .transient
        popover.animates = true

        loadPanel()
        refreshHealth()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshHealth() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        ["mcOpenDashboard", "mcDecision", "mcReload", "mcOptimize"].forEach {
            web?.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
    }

    private func loadPanel() {
        let path = "\(mcHome)/panel.html"
        let url = URL(fileURLWithPath: path)
        web.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: mcHome, isDirectory: true))
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshHealth()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openDashboard(tab: String) {
        var components = URLComponents(url: URL(fileURLWithPath: "\(mcHome)/index.html"), resolvingAgainstBaseURL: false)
        components?.fragment = tab.isEmpty ? "home" : tab
        if let url = components?.url { NSWorkspace.shared.open(url) }
        popover.performClose(nil)
    }

    private func applyMenuState(_ data: [String: Any]?) {
        let state = data?["state"] as? String ?? "unknown"
        let fresh = data?["fresh"] as? Bool ?? false
        let codes = (data?["issue_codes"] as? [String]) ?? []
        let suffix = codes.isEmpty ? "" : " " + codes.joined(separator: "·")
        let title = !fresh ? "MC ?" : (state == "green" ? "MC" : "MC\(suffix.isEmpty ? " !" : suffix)")
        let color: NSColor
        if !fresh {
            color = .systemOrange
        } else {
            switch state {
            case "red": color = .systemRed
            case "yellow": color = .systemOrange
            default: color = .labelColor
            }
        }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: state == "green" && fresh ? .semibold : .bold)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: color, .font: font]
        )
        let headline = data?["headline"] as? String ?? "System health is unavailable"
        statusItem.button?.toolTip = headline
        statusItem.button?.setAccessibilityLabel("Mission Control. \(headline)")
    }

    private func refreshHealth() {
        guard !healthRefreshInFlight else { return }
        healthRefreshInFlight = true
        let executable = healthBin
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = runProcess(executable, [])
            var payload: [String: Any]?
            if result.0 == 0,
               let data = result.1.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any],
               dictionary["schema"] as? String == "mission-control-resource-health-v1" {
                payload = dictionary
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.healthRefreshInFlight = false
                self.lastHealth = payload
                self.applyMenuState(payload)
                self.pushHealthToPanel()
            }
        }
    }

    private func pushHealthToPanel() {
        guard let health = lastHealth else { return }
        let script = "if(window.MCPanelReceiveHealth){window.MCPanelReceiveHealth(\(jsonLiteral(health)));}"
        web.evaluateJavaScript(script, completionHandler: nil)
    }

    private func completePanelAction(ok: Bool, message: String) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = clean.split(separator: "\n").prefix(2).joined(separator: " · ")
        let summary = lines.isEmpty ? (ok ? "Action completed." : "Action failed.") : String(lines)
        let script = "if(window.MCPanelActionComplete){window.MCPanelActionComplete(\(ok ? "true" : "false"),\(jsonLiteral([summary]).dropFirst().dropLast()));}"
        web.evaluateJavaScript(script, completionHandler: nil)
    }

    private func runDashboardDecision(id: String, option: Int) {
        let dashboard = "\(mcHome)/bin/dashboard"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runProcess(dashboard, ["decide", "answer", id, String(option)])
            DispatchQueue.main.async {
                guard let self else { return }
                self.completePanelAction(ok: result.0 == 0, message: result.1)
                if result.0 == 0 { self.loadPanel() }
            }
        }
    }

    private func confirmEmergencyOptimize() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Run more aggressive cleanup?"
        alert.informativeText = "This may close only finished task helpers that Memory Guard revalidates as safe. It will not close protected apps, restart the Mac, or delete disk caches."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Optimize harder")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func runOptimize(mode: String) {
        let args = mode == "emergency" ? ["optimize", "--emergency", "--yes"] : ["optimize", "--apply"]
        let executable = governorBin
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runProcess(executable, args)
            DispatchQueue.main.async {
                guard let self else { return }
                self.completePanelAction(ok: result.0 == 0, message: result.1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshHealth() }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushHealthToPanel()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "mcOpenDashboard":
            openDashboard(tab: message.body as? String ?? "home")
        case "mcReload":
            loadPanel()
        case "mcDecision":
            guard let body = message.body as? [String: Any],
                  let id = body["id"] as? String,
                  !id.isEmpty,
                  let option = body["q"] as? Int,
                  (1...3).contains(option) else {
                completePanelAction(ok: false, message: "Decision payload was invalid.")
                return
            }
            runDashboardDecision(id: id, option: option)
        case "mcOptimize":
            guard let mode = message.body as? String, mode == "apply" || mode == "emergency" else {
                completePanelAction(ok: false, message: "Optimize mode was invalid.")
                return
            }
            if mode == "emergency" && !confirmEmergencyOptimize() {
                completePanelAction(ok: true, message: "Aggressive optimize canceled. Nothing changed.")
                return
            }
            runOptimize(mode: mode)
        default:
            break
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
