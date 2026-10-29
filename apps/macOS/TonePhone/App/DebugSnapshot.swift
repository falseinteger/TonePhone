//
//  DebugSnapshot.swift
//  TonePhone
//
//  Debug builds only: writes PNG images of TonePhone's own windows on request.
//  Used to produce README screenshots without Screen Recording permission.
//
//  Trigger from Terminal:
//    swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.falseinteger.tonephone.snapshot"), object: "/tmp/shots/name", userInfo: nil, deliverImmediately: true)'
//
//  Launch with `-TPAppearance dark` (or `light`) to check an appearance
//  without changing the system setting.
//
//  `io.falseinteger.tonephone.dial` (object = number or SIP address) places
//  a call as if it was typed, so calls can be tested without the keyboard.
//

#if DEBUG
import AppKit

enum DebugSnapshot {
    static let notificationName = Notification.Name("io.falseinteger.tonephone.snapshot")
    static let dialNotificationName = Notification.Name("io.falseinteger.tonephone.dial")

    private static var observer: NSObjectProtocol?
    private static var dialObserver: NSObjectProtocol?

    /// Starts listening for snapshot requests.
    static func install() {
        guard observer == nil else { return }
        switch UserDefaults.standard.string(forKey: "TPAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            let prefix = notification.object as? String ?? NSTemporaryDirectory() + "tonephone"
            MainActor.assumeIsolated { capture(prefix: prefix) }
        }
        dialObserver = DistributedNotificationCenter.default().addObserver(
            forName: dialNotificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let number = notification.object as? String else { return }
            MainActor.assumeIsolated { AppViewModel.shared.dial(number) }
        }
    }

    /// Writes `<prefix>-<window title>.png` for every visible window.
    @MainActor
    private static func capture(prefix: String) {
        for window in NSApp.windows where window.isVisible {
            guard let frameView = window.contentView?.superview else { continue }
            let bounds = frameView.bounds
            guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            frameView.cacheDisplay(in: bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }

            let title = window.title.isEmpty ? "window-\(window.windowNumber)" : window.title
            let safeTitle = title.replacingOccurrences(of: "/", with: "-")
            let url = URL(fileURLWithPath: "\(prefix)-\(safeTitle).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
#endif
