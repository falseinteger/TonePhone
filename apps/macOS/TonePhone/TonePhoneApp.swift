//
//  TonePhoneApp.swift
//  TonePhone
//
//  Main application entry point.
//

import SwiftUI

@main
struct TonePhoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowConfigurator())
                .handlesExternalEvents(preferring: ["main"], allowing: ["main"])
        }
        .handlesExternalEvents(matching: ["main"])
        .commands {
            // Remove "New Window" command (Cmd+N)
            CommandGroup(replacing: .newItem) {}

            // Override "About TonePhone" to open Settings on About tab
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
        }

        Settings {
            SettingsWindowView()
        }
    }
}

/// Menu item for "About TonePhone" that opens Settings on the About tab.
struct AboutMenuItem: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            AboutMenuItem14()
        } else {
            Button("About TonePhone") {
                NotificationCenter.default.post(name: .showAboutSettings, object: nil)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

@available(macOS 14.0, *)
private struct AboutMenuItem14: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("About TonePhone") {
            NotificationCenter.default.post(name: .showAboutSettings, object: nil)
            openSettings()
        }
    }
}

/// App delegate for application lifecycle.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

/// Window delegate to enforce size constraints.
class WindowDelegate: NSObject, NSWindowDelegate {
    static let minSize = NSSize(width: 340, height: 450)
    static let maxSize = NSSize(width: 500, height: 700)

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var newSize = frameSize
        newSize.width = max(Self.minSize.width, min(Self.maxSize.width, newSize.width))
        newSize.height = max(Self.minSize.height, min(Self.maxSize.height, newSize.height))
        return newSize
    }
}

/// Helper view to configure the NSWindow with delegate.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureWindow(window, delegate: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> WindowDelegate {
        WindowDelegate()
    }

    private func configureWindow(_ window: NSWindow, delegate: WindowDelegate) {
        // Set delegate for resize control
        window.delegate = delegate

        // Disable tabs - this is a single-window app
        window.tabbingMode = .disallowed

        // Set size constraints
        window.minSize = WindowDelegate.minSize
        window.maxSize = WindowDelegate.maxSize

        // Enforce current size within bounds
        var frame = window.frame
        let needsResize = frame.width < WindowDelegate.minSize.width ||
                          frame.height < WindowDelegate.minSize.height ||
                          frame.width > WindowDelegate.maxSize.width ||
                          frame.height > WindowDelegate.maxSize.height
        frame.size.width = max(WindowDelegate.minSize.width, min(WindowDelegate.maxSize.width, frame.width))
        frame.size.height = max(WindowDelegate.minSize.height, min(WindowDelegate.maxSize.height, frame.height))
        if needsResize {
            window.setFrame(frame, display: true)
        }
    }
}
