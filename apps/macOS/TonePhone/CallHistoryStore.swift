//
//  CallHistoryStore.swift
//  TonePhone
//
//  Persistent storage for call history records.
//  Stores per-account call records as JSON in Application Support.
//

import Foundation

/// Direction of a call.
enum CallDirection: String, Codable {
    case inbound
    case outbound
    case missed
}

/// A single call history record.
struct CallRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let accountID: UUID
    let remoteURI: String
    let remoteName: String?
    let direction: CallDirection
    let timestamp: Date
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        accountID: UUID,
        remoteURI: String,
        remoteName: String? = nil,
        direction: CallDirection,
        timestamp: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.accountID = accountID
        self.remoteURI = remoteURI
        self.remoteName = remoteName
        self.direction = direction
        self.timestamp = timestamp
        self.duration = duration
    }
}

/// Manages persistent storage for call history.
///
/// Records are stored as JSON in Application Support, limited to
/// a configurable maximum per account (ring buffer).
final class CallHistoryStore {
    static let shared = CallHistoryStore()

    /// Maximum records per account.
    private let maxRecordsPerAccount = 100

    private let fileURL: URL
    private var records: [CallRecord] = []

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not available")
        }

        let tonePhoneDir = appSupport.appendingPathComponent("TonePhone", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tonePhoneDir,
            withIntermediateDirectories: true
        )

        fileURL = tonePhoneDir.appendingPathComponent("call_history.json")
        records = loadFromDisk()
    }

    // MARK: - Public API

    /// Returns all records for a given account, newest first.
    func records(for accountID: UUID) -> [CallRecord] {
        records
            .filter { $0.accountID == accountID }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Adds a call record, trimming old entries if over the limit.
    func addRecord(_ record: CallRecord) {
        records.append(record)
        trimRecords(for: record.accountID)
        saveToDisk()
    }

    /// Deletes a single record by ID.
    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Deletes all records for a given account.
    func clearHistory(for accountID: UUID) {
        records.removeAll { $0.accountID == accountID }
        saveToDisk()
    }

    /// Deletes all records.
    func clearAll() {
        records.removeAll()
        saveToDisk()
    }

    // MARK: - Private

    private func trimRecords(for accountID: UUID) {
        let accountRecords = records
            .filter { $0.accountID == accountID }
            .sorted { $0.timestamp > $1.timestamp }

        if accountRecords.count > maxRecordsPerAccount {
            let toRemove = Set(accountRecords.dropFirst(maxRecordsPerAccount).map(\.id))
            records.removeAll { toRemove.contains($0.id) }
        }
    }

    private func loadFromDisk() -> [CallRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([CallRecord].self, from: data)
        } catch {
            print("Failed to load call history: \(error)")
            return []
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save call history: \(error)")
        }
    }
}
