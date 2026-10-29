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

#if DEBUG
import AppKit

enum DebugSnapshot {
    static let notificationName = Notification.Name("io.falseinteger.tonephone.snapshot")

    private static var observer: NSObjectProtocol?

    /// Starts listening for snapshot requests.
    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            let prefix = notification.object as? String ?? NSTemporaryDirectory() + "tonephone"
            MainActor.assumeIsolated { capture(prefix: prefix) }
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
