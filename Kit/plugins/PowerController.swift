//
//  PowerController.swift
//  Kit
//

import Cocoa
import IOKit.pwr_mgt

public enum PowerControlResult {
    case success
    case requiresApproval
    case failed(String)
}

public final class PowerController {
    public static let shared = PowerController()

    private var displayAssertion: IOPMAssertionID = 0
    private var helperInvalidationObserver: NSObjectProtocol?

    private init() {
        self.helperInvalidationObserver = NotificationCenter.default.addObserver(
            forName: .privilegedHelperConnectionInvalidated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreLidStateAfterHelperRestart()
        }
    }

    deinit {
        if let observer = self.helperInvalidationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var lidNoSleepEnabled: Bool {
        return Store.shared.bool(key: "lid_no_sleep_state", defaultValue: false)
    }

    public var keepScreenAwakeEnabled: Bool {
        return Store.shared.bool(key: "keep_screen_awake_state", defaultValue: false)
    }

    public func setLidNoSleep(_ enabled: Bool, completion: @escaping (PowerControlResult) -> Void) {
        SMCHelper.shared.setLidSleepPrevention(enabled) { result in
            if case .success = result {
                Store.shared.set(key: "lid_no_sleep_state", value: enabled)
                NotificationCenter.default.post(name: .powerStateChanged, object: nil)
            }
            completion(result)
        }
    }

    @discardableResult
    public func setKeepScreenAwake(_ enabled: Bool) -> Bool {
        let success = self.updateDisplayAssertion(enabled)
        if success {
            Store.shared.set(key: "keep_screen_awake_state", value: enabled)
            NotificationCenter.default.post(name: .powerStateChanged, object: nil)
        }
        return success
    }

    public func restoreFromStore() {
        if self.lidNoSleepEnabled {
            if SMCHelper.shared.isInstalled {
                self.setLidNoSleep(true) { result in
                    if case .success = result { return }
                    self.clearLidState()
                }
            } else {
                self.clearLidState()
            }
        }

        if self.keepScreenAwakeEnabled, !self.setKeepScreenAwake(true) {
            Store.shared.set(key: "keep_screen_awake_state", value: false)
            NotificationCenter.default.post(name: .powerStateChanged, object: nil)
        }
    }

    public func uninstallHelper(completion: @escaping (PowerControlResult) -> Void) {
        guard self.lidNoSleepEnabled else {
            SMCHelper.shared.uninstall {
                completion(.success)
            }
            return
        }

        self.setLidNoSleep(false) { result in
            guard case .success = result else {
                completion(result)
                return
            }
            SMCHelper.shared.uninstall {
                completion(.success)
            }
        }
    }

    private func updateDisplayAssertion(_ enabled: Bool) -> Bool {
        if enabled {
            guard self.displayAssertion == 0 else { return true }

            var assertion: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Stats - keep display awake" as CFString,
                &assertion
            )
            guard result == kIOReturnSuccess else {
                NSLog("PowerController: failed to create display assertion: \(result)")
                return false
            }
            self.displayAssertion = assertion
            return true
        }

        guard self.displayAssertion != 0 else { return true }
        let result = IOPMAssertionRelease(self.displayAssertion)
        guard result == kIOReturnSuccess else {
            NSLog("PowerController: failed to release display assertion: \(result)")
            return false
        }
        self.displayAssertion = 0
        return true
    }

    private func restoreLidStateAfterHelperRestart() {
        guard self.lidNoSleepEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard self.lidNoSleepEnabled else { return }
            guard SMCHelper.shared.isInstalled else {
                self.clearLidState()
                return
            }
            self.setLidNoSleep(true) { result in
                if case .success = result { return }
                self.clearLidState()
            }
        }
    }

    private func clearLidState() {
        Store.shared.set(key: "lid_no_sleep_state", value: false)
        NotificationCenter.default.post(name: .powerStateChanged, object: nil)
    }
}

public final class PowerToggleCoordinator: NSObject {
    private weak var lidSwitch: NSSwitch?
    private weak var displaySwitch: NSSwitch?

    public override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.powerStateChanged(_:)),
            name: .powerStateChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .powerStateChanged, object: nil)
    }

    public func bind(lidSwitch: NSSwitch, displaySwitch: NSSwitch) {
        self.lidSwitch = lidSwitch
        self.displaySwitch = displaySwitch
        self.synchronize()
    }

    @objc public func synchronize() {
        self.lidSwitch?.state = PowerController.shared.lidNoSleepEnabled ? .on : .off
        self.displaySwitch?.state = PowerController.shared.keepScreenAwakeEnabled ? .on : .off
    }

    @objc private func powerStateChanged(_ notification: Notification) {
        self.synchronize()
    }

    @objc public func toggleLidNoSleep(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        sender.isEnabled = false
        PowerController.shared.setLidNoSleep(enabled) { result in
            sender.isEnabled = true
            self.synchronize()
            presentPowerControlFailure(result)
        }
    }

    @objc public func toggleKeepScreenAwake(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        if !PowerController.shared.setKeepScreenAwake(enabled) {
            self.synchronize()
        }
    }
}

public func presentPowerControlFailure(_ result: PowerControlResult) {
    switch result {
    case .success:
        return
    case .requiresApproval:
        let alert = NSAlert()
        alert.messageText = localizedString("Background permission required")
        alert.informativeText = localizedString(
            "Allow Stats in System Settings > General > Login Items, then turn the setting on again."
        )
        alert.addButton(withTitle: localizedString("Open Login Items"))
        alert.addButton(withTitle: localizedString("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            SMCHelper.shared.openLoginItems()
        }
    case let .failed(message):
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizedString("Could not update the power setting")
        alert.informativeText = message
        alert.addButton(withTitle: localizedString("OK"))
        alert.runModal()
    }
}
