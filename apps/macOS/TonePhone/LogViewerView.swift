//
//  LogViewerView.swift
//  TonePhone
//
//  Live view of the TonePhone log with filtering, search and export.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One log entry. SIP messages span several lines and stay one entry.
struct LogEntry: Identifiable, Hashable {
    enum Level: Int, CaseIterable, Comparable {
        case error, warning, info, debug, trace

        init(tag: String) {
            switch tag.trimmingCharacters(in: .whitespaces) {
            case "ERROR": self = .error
            case "WARN": self = .warning
            case "DEBUG": self = .debug
            case "TRACE": self = .trace
            default: self = .info
            }
        }

        var title: String {
            switch self {
            case .error: return "Error"
            case .warning: return "Warning"
            case .info: return "Info"
            case .debug: return "Debug"
            case .trace: return "Trace"
            }
        }

        var symbolName: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle"
            case .debug, .trace: return "ladybug"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            default: return .secondary
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: Int
    let time: String
    let level: Level
    var message: String

    var isSIPMessage: Bool { message.hasPrefix("tp_core: SIP ") }

    /// The entry as it appears in the log file.
    var text: String { "\(time) [\(level.title.uppercased())] \(message)" }
}

/// Reads the log file and follows new lines as they are written.
@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var logPath: String?

    /// Only the end of a large log is loaded so the window opens quickly.
    private static let initialReadLimit: UInt64 = 2 * 1024 * 1024

    private var offset: UInt64 = 0
    private var partialLine = ""
    private var nextID = 0
    private var timer: Timer?

    func start() {
        logPath = TonePhoneCore.shared.getLogFilePath()
        reload()
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readNewData() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Hides everything currently shown; new lines keep appearing.
    func clear() {
        entries.removeAll()
    }

    func reload() {
        entries.removeAll()
        partialLine = ""
        guard let logPath, let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > Self.initialReadLimit ? size - Self.initialReadLimit : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = start + UInt64(data.count)

        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            // Drop the partial first line
            text = String(text[text.index(after: firstNewline)...])
        }
        append(text)
    }

    private func readNewData() {
        guard let logPath else { return }
        TonePhoneCore.shared.flushLogs()

        let attributes = try? FileManager.default.attributesOfItem(atPath: logPath)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0

        if size < offset {
            // The log was rotated
            reload()
            return
        }
        guard size > offset, let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? handle.close() }

        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        append(String(decoding: data, as: UTF8.self))
    }

    /// Parses text into entries. Lines without a timestamp continue the previous entry.
    private func append(_ text: String) {
        let combined = partialLine + text
        var lines = combined.components(separatedBy: "\n")
        partialLine = lines.removeLast()

        var newEntries: [LogEntry] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if let entry = parseEntry(line) {
                newEntries.append(entry)
            } else if !line.isEmpty {
                if newEntries.isEmpty, !entries.isEmpty {
                    entries[entries.count - 1].message += "\n" + line
                } else if !newEntries.isEmpty {
                    newEntries[newEntries.count - 1].message += "\n" + line
                }
            }
        }

        entries.append(contentsOf: newEntries)
        if entries.count > 20_000 {
            entries.removeFirst(entries.count - 20_000)
        }
    }

    /// Parses `2026-01-01 12:00:00 [INFO ] message`.
    private func parseEntry(_ line: String) -> LogEntry? {
        guard line.count > 21,
              line.dropFirst(4).first == "-",
              let open = line.firstIndex(of: "["),
              let close = line[open...].firstIndex(of: "]") else { return nil }

        let time = String(line[..<open]).trimmingCharacters(in: .whitespaces)
        let tag = String(line[line.index(after: open)..<close])
        var messageStart = line.index(after: close)
        if messageStart < line.endIndex, line[messageStart] == " " {
            messageStart = line.index(after: messageStart)
        }

        defer { nextID += 1 }
        return LogEntry(id: nextID, time: time, level: LogEntry.Level(tag: tag), message: String(line[messageStart...]))
    }
}

/// Saves the current log file with a save panel.
enum LogExporter {
    @MainActor
    static func export() {
        TonePhoneCore.shared.flushLogs()
        guard let logPath = TonePhoneCore.shared.getLogFilePath() else { return }

        let panel = NSSavePanel()
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "TonePhone Log \(stamp).txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: logPath), to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The log couldn’t be exported."
            alert.runModal()
        }
    }
}

/// The Logs window.
struct LogViewerView: View {
    static let windowID = "logs"

    private enum Scope: String, CaseIterable {
        case all = "All"
        case sip = "SIP Messages"
        case problems = "Problems"
    }

    @StateObject private var store = LogStore()
    @ObservedObject private var settings = SettingsStore.shared
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var isPaused = false
    @State private var selection = Set<LogEntry.ID>()
    @State private var pausedEntries: [LogEntry] = []

    private var visibleEntries: [LogEntry] {
        let source = isPaused ? pausedEntries : store.entries
        return source.filter { entry in
            switch scope {
            case .all: break
            case .sip: guard entry.isSIPMessage else { return false }
            case .problems: guard entry.level <= .warning else { return false }
            }
            return query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Table(visibleEntries, selection: $selection) {
                TableColumn("Time") { entry in
                    Text(entry.time.split(separator: " ").last.map(String.init) ?? entry.time)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .width(min: 64, ideal: 70, max: 90)

                TableColumn("Level") { entry in
                    Label(entry.level.title, systemImage: entry.level.symbolName)
                        .foregroundStyle(entry.level.color)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .width(min: 70, ideal: 84, max: 100)

                TableColumn("Message") { entry in
                    Text(entry.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(entry.isSIPMessage ? nil : 4)
                }
            }
            .onChange(of: store.entries.count) { _ in
                guard !isPaused, query.isEmpty, let last = visibleEntries.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .overlay {
                if visibleEntries.isEmpty {
                    Text(store.logPath == nil ? "Logging Is Unavailable" : "No Log Entries")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Filter log entries")
            }

            ToolbarItemGroup {
                Toggle(isOn: $settings.sipTrace) {
                    Label("Log SIP Messages", systemImage: "arrow.left.arrow.right")
                }
                .help("Record every SIP message sent and received")

                Toggle(isOn: Binding(
                    get: { isPaused },
                    set: { paused in
                        pausedEntries = paused ? store.entries : []
                        isPaused = paused
                    }
                )) {
                    Label("Pause", systemImage: "pause")
                }
                .help("Stop following new entries")

                Button {
                    store.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear the entries shown in this window (the log file is kept)")

                Button {
                    LogExporter.export()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Save the log file")
            }
        }
        .onCopyCommand {
            let selected = visibleEntries.filter { selection.contains($0.id) }
            let text = selected.map(\.text).joined(separator: "\n")
            return [NSItemProvider(object: text as NSString)]
        }
        .navigationTitle("Logs")
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            store.start()
            // Opening the log viewer turns on diagnostics
            if !settings.advancedMode { settings.advancedMode = true }
        }
        .onDisappear { store.stop() }
    }
}
