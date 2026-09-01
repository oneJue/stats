//
//  PowerSettings.swift
//  Helper
//

import Foundation
import IOKit

final class PowerSettings {
    enum SettingsError: LocalizedError {
        case missingPowerService
        case unreadableSleepState
        case commandFailed(String)
        case stateMismatch(expected: Bool, actual: Bool)
        case rollbackFailed(update: String, rollback: String)

        var errorDescription: String? {
            switch self {
            case .missingPowerService:
                return "IOPMrootDomain is unavailable"
            case .unreadableSleepState:
                return "SleepDisabled is unavailable"
            case let .commandFailed(message):
                return message
            case let .stateMismatch(expected, actual):
                return "SleepDisabled verification failed (expected \(expected), actual \(actual))"
            case let .rollbackFailed(update, rollback):
                return "Power update failed (\(update)); rollback will be retried (\(rollback))"
            }
        }
    }

    private struct Journal: Codable {
        let previousSleepDisabled: Bool
    }

    private static let defaultJournalURL = URL(
        fileURLWithPath: "/Library/Application Support/Stats/power-session.json"
    )

    private let journalURL: URL
    private let stateReader: () throws -> Bool
    private let stateWriter: (Bool) throws -> Void

    convenience init() {
        self.init(
            journalURL: Self.defaultJournalURL,
            stateReader: Self.readSleepDisabled,
            stateWriter: Self.writeSleepDisabled
        )
    }

    init(
        journalURL: URL,
        stateReader: @escaping () throws -> Bool,
        stateWriter: @escaping (Bool) throws -> Void
    ) {
        self.journalURL = journalURL
        self.stateReader = stateReader
        self.stateWriter = stateWriter
    }

    func recoverInterruptedSession() throws {
        guard let journal = try self.readJournal() else { return }
        try self.apply(journal.previousSleepDisabled)
        try FileManager.default.removeItem(at: self.journalURL)
    }

    func setLidSleepPrevention(_ enabled: Bool) throws {
        if enabled {
            if try self.readJournal() != nil {
                try self.apply(true)
                return
            }

            let previousState = try self.stateReader()
            try self.writeJournal(Journal(previousSleepDisabled: previousState))
            do {
                try self.apply(true)
            } catch let updateError {
                do {
                    try self.apply(previousState)
                    try self.removeJournal()
                } catch let rollbackError {
                    throw SettingsError.rollbackFailed(
                        update: updateError.localizedDescription,
                        rollback: rollbackError.localizedDescription
                    )
                }
                throw updateError
            }
            return
        }

        guard let journal = try self.readJournal() else { return }
        try self.apply(journal.previousSleepDisabled)
        try self.removeJournal()
    }

    private func apply(_ enabled: Bool) throws {
        try self.stateWriter(enabled)
        let actual = try self.stateReader()
        guard actual == enabled else {
            throw SettingsError.stateMismatch(expected: enabled, actual: actual)
        }
    }

    private func readJournal() throws -> Journal? {
        guard FileManager.default.fileExists(atPath: self.journalURL.path) else { return nil }
        return try JSONDecoder().decode(Journal.self, from: Data(contentsOf: self.journalURL))
    }

    private func writeJournal(_ journal: Journal) throws {
        try FileManager.default.createDirectory(
            at: self.journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(journal).write(to: self.journalURL, options: .atomic)
    }

    private func removeJournal() throws {
        try FileManager.default.removeItem(at: self.journalURL)
    }

    private static func readSleepDisabled() throws -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { throw SettingsError.missingPowerService }
        defer { IOObjectRelease(service) }

        guard let raw = IORegistryEntryCreateCFProperty(
            service,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            throw SettingsError.unreadableSleepState
        }
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        throw SettingsError.unreadableSleepState
    }

    private static func writeSleepDisabled(_ enabled: Bool) throws {
        let process = Process()
        let errorPipe = Pipe()
        defer { errorPipe.fileHandleForReading.closeFile() }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", enabled ? "1" : "0"]
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SettingsError.commandFailed(message.flatMap { $0.isEmpty ? nil : $0 } ?? "pmset failed")
        }
    }
}
