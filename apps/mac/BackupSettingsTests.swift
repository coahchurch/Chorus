import Foundation
import Testing
@testable import PresenterCore

@Suite("BackupSettings portability and staging")
struct BackupSettingsTests {
    private final class EphemeralDefaults: UserDefaults {
        private var store: [String: Any] = [:]
        override func object(forKey defaultName: String) -> Any? { store[defaultName] }
        override func set(_ value: Any?, forKey defaultName: String) {
            if let value { store[defaultName] = value } else { store.removeValue(forKey: defaultName) }
        }
        override func removeObject(forKey defaultName: String) { store.removeValue(forKey: defaultName) }
        override func dictionary(forKey defaultName: String) -> [String : Any]? { store[defaultName] as? [String: Any] }
        override func dictionaryRepresentation() -> [String : Any] { store }
    }

    @Test func snapshotFiltersToPortableKeys() {
        let defaults = EphemeralDefaults()
        // Portable keys
        defaults.set(["a":1], forKey: "audio.mixFolders")
        defaults.set(true, forKey: "present.continuous")
        // Non-portable key
        defaults.set("/private/tmp", forKey: "device.specific.path")

        let snap = BackupSettings.snapshot(defaults: defaults)
        #expect(snap.keys.contains("audio.mixFolders"))
        #expect(snap.keys.contains("present.continuous"))
        #expect(!snap.keys.contains("device.specific.path"))
    }

    @Test func stageHonorsKeepMinePolicyAndApplyClearsPending() {
        let defaults = EphemeralDefaults()
        defaults.set("mine", forKey: "present.activeLayoutID")
        let incoming: [String: Any] = [
            "present.activeLayoutID": "theirs",
            "audio.fadeEnabled": true
        ]
        let staged = BackupSettings.stage(incoming, policy: .keepMine, defaults: defaults)
        #expect(staged == 1, "only audio.fadeEnabled should stage")
        // Pending should exist and include only portable keys
        var pending = defaults.dictionary(forKey: BackupSettings.pendingKey) ?? [:]
        #expect(pending["audio.fadeEnabled"] as? Bool == true)
        #expect(pending["present.activeLayoutID"] == nil)

        // Apply
        BackupSettings.applyPending(defaults: defaults)
        #expect(defaults.object(forKey: BackupSettings.pendingKey) == nil)
        #expect(defaults.object(forKey: "audio.fadeEnabled") as? Bool == true)
        #expect(defaults.object(forKey: "present.activeLayoutID") as? String == "mine")
    }
}
