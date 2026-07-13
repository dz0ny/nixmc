import SwiftUI
import AppKit

private extension Notification.Name {
    static let showMainWindow = Notification.Name("nixmc.showMainWindow")
}

/// nixmc starts as a menu-bar utility and only becomes a regular app when the
/// user explicitly opens its main window. Closing that window returns it to
/// accessory mode while leaving the menu-bar controls available.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // A machine without a canonical nix-darwin configuration needs the
        // bootstrap window immediately. Configured machines stay menu-bar-only
        // until the user asks to see the main window.
        NSApp.setActivationPolicy(Paths().hasCanonicalConfig ? .accessory : .regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Honor a persisted Light/Dark override before the first frame.
        MainActor.assumeIsolated { AppSettings.shared.applyAppearance() }
        TeamRecipeStore.shared.startAutomaticFetch()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        if !Paths().hasCanonicalConfig {
            // MenuBarExtra's host is installed during application startup.
            // Defer one turn so it can receive the request to open setup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .showMainWindow, object: nil)
            }
        }

    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Finder/Dock launches of an already-running accessory app do not
        // create a window automatically. Reuse the menu-bar open action.
        if !flag {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showMainWindow, object: nil)
            }
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeMain && !(window is NSPanel)
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow
#if compiler(>=6.4)
    @Environment(\.openSettings) private var openSettings
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NixMC")
                .font(.headline)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(app.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        Divider()
        Button(action: showMainWindow) {
            Label("Open NixMC", systemImage: "macwindow")
        }
        Button { app.refresh() } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        Button { app.checkForUpdatesNow() } label: {
            Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
        }
            .disabled(app.phase != .ready || app.updateChecking)
        Divider()
        Button(action: showSettings) {
            Label("Settings…", systemImage: "gearshape")
        }
        Button { NSApp.terminate(nil) } label: {
            Label("Quit", systemImage: "power")
        }
            .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
                showMainWindow()
            }
    }

    private var statusColor: Color {
        switch app.menuBarStatus {
        case .idle: .green
        case .working: .blue
        case .reviewNeeded: .orange
        case .updateAvailable: .green
        case .attentionNeeded: .red
        }
    }

    private func showMainWindow() {
        activateAsRegularApp()
        if let window = NSApp.windows.first(where: { $0.title == "NixMC" && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.title == "NixMC" && $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
                // A close notification from the previous window can arrive on
                // this run-loop turn. Reassert regular mode after this window
                // is actually visible so the Dock follows the shown app UI.
                activateAsRegularApp()
            }
        }
    }

    private func showSettings() {
        activateAsRegularApp()
#if compiler(>=6.4)
        if #available(macOS 26.0, *) {
            openSettings()
            return
        }
#endif
        // Older macOS releases, and the older SwiftUI SDK used in CI, do not
        // expose `openSettings`. The Settings scene registers this action.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func activateAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var app: AppState

    var body: some View {
        let status = app.menuBarStatus
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Circle()
                .fill(overlayColor(for: status))
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1))
                .offset(x: 1, y: 1)
        }
        .frame(width: 20, height: 20)
        .fixedSize()
        .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(status.label)
            .help(status.label)
    }

    private func overlayColor(for status: AppState.MenuBarStatus) -> Color {
        switch status {
        case .idle: .secondary.opacity(0.8)
        case .working: .blue
        case .reviewNeeded: .orange
        case .updateAvailable: .green
        case .attentionNeeded: .red
        }
    }

}

@main
struct NixmcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    /// Shared singleton, observed here so the scenes re-evaluate on theme /
    /// appearance changes.
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("NixMC", id: "main") {
            mainContent
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Increase Help Text Size") { app.increaseHelpTextSize() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Decrease Help Text Size") { app.decreaseHelpTextSize() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Reset Help Text Size") { app.resetHelpTextSize() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(settings)
        }

        MenuBarExtra {
            MenuBarContent(app: app)
        } label: {
            MenuBarStatusLabel(app: app)
        }
        .menuBarExtraStyle(.menu)
    }

    private var mainContent: some View {
        ContentView()
            .environmentObject(app)
            .environmentObject(settings)
            // Remount when the accent theme changes: `Theme.*` lookups are
            // static (not observed), so views must re-read the new palette.
            .id(settings.themeID)
    }

}
