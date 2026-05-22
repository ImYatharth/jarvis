//
//  JarvisApp.swift
//  Jarvis
//
//  Menu bar-only Jarvis app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with Jarvis voice controls.
//

import Combine
import ServiceManagement
import SwiftUI

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(JarvisAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

/// Manages the Jarvis lifecycle: creates the menu bar panel and starts
/// the Jarvis voice pipeline on launch.
@MainActor
final class JarvisAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private let orbitManager = JarvisManager()
    private var responseOverlayManager: JarvisResponseOverlayManager?
    private var responseOverlayCancellable: AnyCancellable?
    private let installedBundlePath = "/Applications/Jarvis.app"

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🤖 Jarvis: Starting...")
        print("🤖 Jarvis: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        JarvisAnalytics.configure()
        JarvisAnalytics.trackAppOpened()

        menuBarPanelManager = MenuBarPanelManager(orbitManager: orbitManager)
        responseOverlayManager = JarvisResponseOverlayManager(jarvisManager: orbitManager)

        // Observe visibility flag to show / hide the response overlay
        responseOverlayCancellable = orbitManager.$isResponseOverlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.responseOverlayManager?.showOrUpdate()
                } else {
                    self.responseOverlayManager?.hide()
                }
            }

        orbitManager.start()
        // Auto-open the panel if the user still needs to do something:
        // either they haven't onboarded yet, or permissions were revoked.
        if orbitManager.setupStage != .ready {
            menuBarPanelManager?.showPanelOnLaunch()
        }
        registerAsLoginItemIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        orbitManager.stop()
        responseOverlayManager?.dismiss()
    }

    /// Registers the app as a login item so it launches automatically on
    /// startup. Uses SMAppService which shows the app in System Settings >
    /// General > Login Items, letting the user toggle it off if they want.
    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        let currentBundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let isInstalledBundle = currentBundlePath == installedBundlePath
        JarvisSupportLog.append(
            "app",
            "bundlePath=\(currentBundlePath) installedBundle=\(isInstalledBundle) loginItemStatus=\(loginItemService.status.rawValue)"
        )

        if !isInstalledBundle {
            if loginItemService.status == .enabled {
                do {
                    try loginItemService.unregister()
                    JarvisSupportLog.append("app", "unregistered login item for non-installed bundle")
                    print("🤖 Jarvis: Removed login item for non-installed bundle")
                } catch {
                    JarvisSupportLog.append("app", "failed to unregister login item: \(error.localizedDescription)")
                    print("⚠️ Jarvis: Failed to unregister login item: \(error)")
                }
            } else {
                JarvisSupportLog.append("app", "skipped login item registration for non-installed bundle")
            }
            return
        }

        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                JarvisSupportLog.append("app", "registered login item for installed bundle")
                print("🤖 Jarvis: Registered as login item")
            } catch {
                JarvisSupportLog.append("app", "failed to register login item: \(error.localizedDescription)")
                print("⚠️ Jarvis: Failed to register as login item: \(error)")
            }
        } else {
            JarvisSupportLog.append("app", "login item already enabled for installed bundle")
        }
    }
}
