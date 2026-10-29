//
//  TonePhoneApp.swift
//  TonePhone
//
//  Main application entry point: scenes and menu bar commands.
//

import SwiftUI

@main
struct TonePhoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("TonePhone", id: MainWindow.id) {
            ContentView()
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 520, minHeight: 460, idealHeight: 600)
        }
        .defaultSize(width: 380, height: 600)
        .commands {
            TonePhoneCommands()
        }

        Window("Logs", id: LogViewerView.windowID) {
            LogViewerView()
        }
        .defaultSize(width: 860, height: 520)
        // Opened from Window › Logs (⌥⌘L) below instead of the automatic item
        .commandsRemoved()

        Window("Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView()
        }
        .defaultSize(width: 600, height: 640)
        // Opened from the Help menu
        .commandsRemoved()

        Settings {
            SettingsWindowView()
        }
    }
}

/// Menu bar commands. Every call action is available from the Call menu
/// so it can be found and triggered from the keyboard.
struct TonePhoneCommands: Commands {
    @ObservedObject private var viewModel = AppViewModel.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.openWindow) private var openWindow

    private var hasCall: Bool { viewModel.activeCallID != nil }
    private var isConnected: Bool {
        viewModel.callState == .established || viewModel.callState == .held
    }
    private var isRinging: Bool {
        if case .incoming = viewModel.callState { return true }
        return false
    }

    var body: some Commands {
        // Lets non-view code (notifications, incoming calls) reopen the main window
        let _ = MainWindow.store(openWindow)

        CommandGroup(replacing: .appInfo) {
            Button("About TonePhone") {
                AboutPanel.show()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Account…") {
                viewModel.showAddAccountSheet()
            }
            .keyboardShortcut("n")
        }

        CommandMenu("Account") {
            Button("Disconnect") {
                viewModel.disconnect()
            }
            .disabled(viewModel.activeAccount == nil)

            if let account = viewModel.activeAccount {
                Button("Edit “\(account.title)”…") {
                    viewModel.showEditAccountSheet(for: account)
                }
            }
        }

        CommandMenu("Call") {
            Button("Call Voicemail") {
                viewModel.callVoicemail()
            }
            .disabled(!viewModel.canCallVoicemail)

            Divider()

            Button("Answer") {
                viewModel.answerCall()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isRinging)

            Button("Decline") {
                viewModel.hangupCall()
            }
            .disabled(!isRinging)

            Divider()

            Button(viewModel.isMuted ? "Unmute" : "Mute") {
                viewModel.toggleMute()
            }
            .keyboardShortcut("u")
            .disabled(!isConnected)

            Button(viewModel.isOnHold ? "Resume" : "Hold") {
                viewModel.toggleHold()
            }
            .keyboardShortcut("r")
            .disabled(!isConnected)

            Menu("Audio Output") {
                devicePicker(
                    devices: viewModel.outputDevices,
                    selection: viewModel.selectedOutputDevice,
                    onSelect: viewModel.selectOutputDevice
                )
            }

            Menu("Audio Input") {
                devicePicker(
                    devices: viewModel.inputDevices,
                    selection: viewModel.selectedInputDevice,
                    onSelect: viewModel.selectInputDevice
                )
            }

            Divider()

            Button("End Call") {
                viewModel.hangupCall()
            }
            .keyboardShortcut("d")
            .disabled(!hasCall || isRinging)
        }

        CommandGroup(before: .windowList) {
            // Brings the main window back after it was closed
            Button("TonePhone") {
                MainWindow.show()
            }
            .keyboardShortcut("0")

            Button("Logs") {
                openWindow(id: LogViewerView.windowID)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }

        CommandGroup(after: .help) {
            Button("Acknowledgements") {
                openWindow(id: "acknowledgements")
            }
        }
    }

    @ViewBuilder
    private func devicePicker(
        devices: [AudioDevice],
        selection: AudioDevice?,
        onSelect: @escaping (AudioDevice?) -> Void
    ) -> some View {
        Picker("Device", selection: Binding(
            get: { selection?.id ?? "" },
            set: { id in onSelect(devices.first { $0.id == id }) }
        )) {
            Text("System Default").tag("")
            Divider()
            ForEach(devices) { device in
                Text(device.name).tag(device.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

/// Opens and inspects the main window from outside SwiftUI views.
@MainActor
enum MainWindow {
    static let id = "main"
    private static var openWindow: OpenWindowAction?

    static func store(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// Whether the main window is on screen (not closed or minimized).
    static var isVisible: Bool {
        NSApp.windows.contains { $0.identifier?.rawValue == id && $0.isVisible && !$0.isMiniaturized }
    }

    /// Shows the main window, reopening it if it was closed.
    static func show() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }), window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: id)
        }
    }
}

/// The standard About panel with credits.
enum AboutPanel {
    static func show() {
        let credits = NSAttributedString(
            string: "A native SIP softphone for macOS.\nBuilt on baresip and libre.\n\nMIT License · Open Source",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// App delegate for application lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MainActor.assumeIsolated { DebugSnapshot.install() }
        #endif
    }

    /// Keep running when the window closes so incoming calls still ring.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated { MainWindow.show() }
        }
        return true
    }

    /// Unregister cleanly so the server stops routing calls to this Mac.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            try? TonePhoneCore.shared.stop()
        }
    }
}
