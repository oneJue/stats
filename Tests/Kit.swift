//
//  Kit.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 04/07/2026.
//  Using Swift 6.0.
//  Running on macOS 26.5.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import Kit
import IOKit.pwr_mgt

class KitTests: XCTestCase {
    private let displayAssertionName = "Stats - keep display awake"

    private func activePowerAssertionNames() -> Set<String> {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let assertionsByPID = raw?.takeRetainedValue() as NSDictionary?,
              let assertions = assertionsByPID[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] as? [[String: Any]] else {
            return []
        }
        return Set(assertions.compactMap { $0[kIOPMAssertionNameKey as String] as? String })
    }

    func testKeepScreenAwakeAssertionLifecycle() throws {
        let powerController = PowerController.shared
        let previousState = powerController.keepScreenAwakeEnabled
        defer {
            _ = powerController.setKeepScreenAwake(previousState)
        }

        XCTAssertTrue(powerController.setKeepScreenAwake(false))
        XCTAssertFalse(self.activePowerAssertionNames().contains(self.displayAssertionName))

        XCTAssertTrue(powerController.setKeepScreenAwake(true))
        XCTAssertTrue(self.activePowerAssertionNames().contains(self.displayAssertionName))

        XCTAssertTrue(powerController.setKeepScreenAwake(false))
        XCTAssertFalse(self.activePowerAssertionNames().contains(self.displayAssertionName))
    }

    func testIsNewestVersion_release() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.1", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.12.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.12.0", latestVersion: "v2.11.5"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0.0", latestVersion: "v2.99.99"))
    }
    
    func testIsNewestVersion_beta() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta2", latestVersion: "v2.11.0-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta2"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.10.9"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.1-beta1"))
    }
    
    func testIsNewestVersion_malformed() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "", latestVersion: ""))
    }
    
    func testUnitsGetReadableSpeed_byte() throws {
        XCTAssertEqual(Units(bytes: 0).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 999).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 1_000).getReadableSpeed(base: .byte), "1 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte), "500 KB/s")
        XCTAssertEqual(Units(bytes: 2_500_000).getReadableSpeed(base: .byte), "2.5 MB/s")
        XCTAssertEqual(Units(bytes: 150_000_000).getReadableSpeed(base: .byte), "150 MB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000).getReadableSpeed(base: .byte), "2.0 GB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000_000).getReadableSpeed(base: .byte), "2.0 TB/s")
        XCTAssertEqual(Units(bytes: -5).getReadableSpeed(base: .byte), "0 KB/s")
    }
    
    func testUnitsGetReadableSpeed_bit() throws {
        XCTAssertEqual(Units(bytes: 100).getReadableSpeed(base: .bit), "0 Kb/s")
        XCTAssertEqual(Units(bytes: 50_000).getReadableSpeed(base: .bit), "400 Kb/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit), "4.0 Mb/s")
        XCTAssertEqual(Units(bytes: 200_000_000).getReadableSpeed(base: .bit), "1.6 Gb/s")
        XCTAssertEqual(Units(bytes: 200_000_000_000).getReadableSpeed(base: .bit), "1.6 Tb/s")
    }
    
    func testUnitsGetReadableSpeed_fixedUnit() throws {
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "KB"), "500 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "MB"), "0.5 MB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit, unit: "MB"), "4 Mb/s")
    }
}

final class PowerSettingsTests: XCTestCase {
    private final class SleepState {
        var value: Bool
        var writes: [Bool] = []

        init(_ value: Bool) {
            self.value = value
        }
    }

    private var temporaryDirectory: URL!
    private var journalURL: URL {
        return self.temporaryDirectory.appendingPathComponent("power-session.json")
    }

    override func setUpWithError() throws {
        self.temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: self.temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.temporaryDirectory)
    }

    private func settings(_ state: SleepState) -> PowerSettings {
        return PowerSettings(
            journalURL: self.journalURL,
            stateReader: { state.value },
            stateWriter: {
                state.value = $0
                state.writes.append($0)
            }
        )
    }

    func testEnableThenDisableRestoresOriginalState() throws {
        let state = SleepState(false)
        let settings = self.settings(state)

        XCTAssertNoThrow(try settings.setLidSleepPrevention(true))
        XCTAssertTrue(state.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.journalURL.path))

        XCTAssertNoThrow(try settings.setLidSleepPrevention(false))
        XCTAssertFalse(state.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.journalURL.path))
        XCTAssertEqual(state.writes, [true, false])
    }

    func testDisablePreservesOriginallyEnabledState() throws {
        let state = SleepState(true)
        let settings = self.settings(state)

        XCTAssertNoThrow(try settings.setLidSleepPrevention(true))
        XCTAssertNoThrow(try settings.setLidSleepPrevention(false))
        XCTAssertEqual(state.writes, [true, true])
    }

    func testRecoveryRestoresInterruptedSession() throws {
        let state = SleepState(false)
        XCTAssertNoThrow(try self.settings(state).setLidSleepPrevention(true))

        try self.settings(state).recoverInterruptedSession()

        XCTAssertFalse(state.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.journalURL.path))
        XCTAssertEqual(state.writes, [true, false])
    }

    func testFailedEnableRollsBackAndRemovesRecoveryJournal() throws {
        let state = SleepState(false)
        let settings = PowerSettings(
            journalURL: self.journalURL,
            stateReader: { state.value },
            stateWriter: { enabled in
                state.writes.append(enabled)
                state.value = false
            }
        )

        XCTAssertThrowsError(try settings.setLidSleepPrevention(true))
        XCTAssertFalse(state.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.journalURL.path))
        XCTAssertEqual(state.writes, [true, false])
    }

    func testFailedRollbackKeepsRecoveryJournal() throws {
        let settings = PowerSettings(
            journalURL: self.journalURL,
            stateReader: { false },
            stateWriter: { _ in throw PowerSettings.SettingsError.commandFailed("test failure") }
        )

        XCTAssertThrowsError(try settings.setLidSleepPrevention(true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.journalURL.path))
    }

    func testDisableWithoutOwnedSessionLeavesSystemStateUntouched() throws {
        let state = SleepState(true)
        let settings = self.settings(state)

        XCTAssertNoThrow(try settings.setLidSleepPrevention(false))
        XCTAssertTrue(state.value)
        XCTAssertTrue(state.writes.isEmpty)
    }
}
