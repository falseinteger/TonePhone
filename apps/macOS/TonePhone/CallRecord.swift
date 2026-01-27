//
//  CallRecord.swift
//  TonePhone
//
//  Model for storing call history records.
//

import Foundation

/// Represents the direction of a call.
enum CallDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

/// Represents the outcome of a call.
enum CallOutcome: String, Codable, Sendable {
    case answered
    case missed
    case declined
    case failed
}

/// A record of a single call for the call history.
struct CallRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let direction: CallDirection
    let outcome: CallOutcome
    let remoteURI: String
    let remoteName: String?
    let startTime: Date
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        direction: CallDirection,
        outcome: CallOutcome,
        remoteURI: String,
        remoteName: String? = nil,
        startTime: Date = Date(),
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.direction = direction
        self.outcome = outcome
        self.remoteURI = remoteURI
        self.remoteName = remoteName
        self.startTime = startTime
        self.duration = duration
    }

    /// Display name for the call (name if available, otherwise URI).
    var displayName: String {
        if let name = remoteName, !name.isEmpty {
            return name
        }
        // Extract user part from SIP URI
        if remoteURI.lowercased().hasPrefix("sip:") {
            let withoutScheme = String(remoteURI.dropFirst(4))
            if let atIndex = withoutScheme.firstIndex(of: "@") {
                return String(withoutScheme[..<atIndex])
            }
            return withoutScheme
        }
        return remoteURI
    }

    /// Formatted duration string.
    var formattedDuration: String? {
        guard let duration = duration, duration > 0 else { return nil }

        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Formatted time string.
    var formattedTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(startTime) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(startTime) {
            return "Yesterday"
        } else if calendar.isDate(startTime, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }

        return formatter.string(from: startTime)
    }
}

// MARK: - Call History Store

/// Manages persistent storage of call history.
final class CallHistoryStore {
    static let shared = CallHistoryStore()

    private let storageKey = "CallHistory"
    private let maxRecords = 100

    private init() {}

    /// Loads call history from persistent storage.
    func loadHistory() -> [CallRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            let records = try JSONDecoder().decode([CallRecord].self, from: data)
            return records
        } catch {
            print("CallHistoryStore: Failed to load history: \(error)")
            return []
        }
    }

    /// Saves call history to persistent storage.
    func saveHistory(_ records: [CallRecord]) {
        // Keep only the most recent records
        let trimmedRecords = Array(records.prefix(maxRecords))

        do {
            let data = try JSONEncoder().encode(trimmedRecords)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("CallHistoryStore: Failed to save history: \(error)")
        }
    }

    /// Adds a new call record to history.
    func addRecord(_ record: CallRecord) {
        var records = loadHistory()
        records.insert(record, at: 0)
        saveHistory(records)
    }

    /// Clears all call history.
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Deletes a specific record.
    func deleteRecord(id: UUID) {
        var records = loadHistory()
        records.removeAll { $0.id == id }
        saveHistory(records)
    }
}
