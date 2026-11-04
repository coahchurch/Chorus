import SwiftATV
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AppleTVRemoteController {
    private(set) var devices: [AppleTVConfiguration] = []
    private(set) var status = "Not connected"
    private(set) var isScanning = false
    private(set) var isPairing = false
    private(set) var isPairingReady = false
    private(set) var pairingPrompt: String?
    private(set) var isConnecting = false
    private var connected: (any AppleTVDevice)?
    private var pairingHandler: (any PairingHandler)?
    var selectedID: String?

    var selectedDevice: AppleTVConfiguration? {
        devices.first { $0.mainIdentifier == selectedID }
    }

    var hasSavedPairing: Bool {
        guard let device = selectedDevice else { return false }
        return loadVault().settings(for: device).credentials(for: .companion) != nil
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        status = "Scanning for Apple TVs..."
        Task {
            defer { isScanning = false }
            do {
                let found = try await ATVClient.scan(timeout: 5)
                devices = found
                    .filter { $0.deviceInfo.model.isAppleTV }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if selectedID == nil { selectedID = devices.first?.mainIdentifier }
                if devices.isEmpty {
                    status = "No Apple TVs found"
                } else if hasSavedPairing {
                    status = "Paired credentials saved"
                } else {
                    status = "\(devices.count) device\(devices.count == 1 ? "" : "s") found"
                }
            } catch {
                status = "Scan failed: \(error.localizedDescription)"
                DiagnosticsStore.shared.note("appletv.scan.failed", detail: error.localizedDescription)
            }
        }
    }

    func connect() {
        guard let device = selectedDevice else {
            status = "Select an Apple TV first"
            return
        }
        guard !isConnecting else { return }
        isConnecting = true
        status = "Connecting to \(device.name)..."
        Task {
            defer { isConnecting = false }
            do {
                if let connected {
                    await connected.close()
                    self.connected = nil
                }
                let settings = loadVault().settings(for: device)
                let options = ConnectOptions(
                    protocols: [.companion],
                    requestTimeout: 15,
                    runtimeRequestTimeout: 15
                )
                var lastError: Error?
                for attempt in 1...2 {
                    do {
                        connected = try await ATVClient.connect(
                            device,
                            options: options,
                            settings: settings
                        ).device
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        connected = nil
                        if attempt == 1 {
                            status = "Apple TV closed the connection; retrying..."
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                    }
                }
                if let lastError {
                    throw lastError
                }
                status = "Connected to \(device.name)"
            } catch {
                connected = nil
                status = "Connection failed: \(error.localizedDescription)"
                DiagnosticsStore.shared.note("appletv.connect.failed", detail: error.localizedDescription)
            }
        }

    }

    func pair() {
            guard let device = selectedDevice else {
                status = "Select an Apple TV first"
                return
            }
            isPairing = true
            isPairingReady = false
            pairingPrompt = nil
            status = "Starting pairing..."
            Task {
                do {
                    let settings = loadVault().settings(for: device)
                    let handler = try await ATVClient.pair(device, protocol: .companion, settings: settings)
                    try await handler.begin()
                    pairingHandler = handler
                    isPairingReady = true
                    switch handler.pairingCodeDirection {
                    case .deviceProvided:
                        pairingPrompt = "Enter the 4-digit PIN shown on the Apple TV."
                    case .clientProvided(let pin):
                        pairingPrompt = "Enter \(pin) on the Apple TV."
                    }
                    status = "Pairing in progress"
                } catch {
                    isPairing = false
                    isPairingReady = false
                    pairingHandler = nil
                    status = "Pairing failed: \(error.localizedDescription)"
                    DiagnosticsStore.shared.note("appletv.pair.failed", detail: error.localizedDescription)
                }
            }
        }

        func submitPIN(_ pin: String) {
                let normalizedPIN = pin.filter(\.isNumber)
                guard normalizedPIN.count == 4 else {
                    status = "Enter the 4-digit PIN shown on the Apple TV"
                    return
                }
                guard let handler = pairingHandler, let device = selectedDevice else {
                    status = "Pairing is still starting..."
                    return
                }
                Task {
                    do {
                        isPairingReady = false
                        try await handler.pin(normalizedPIN)
                    let pairing = try await handler.finish()
                    var vault = loadVault()
                    let settings = vault.settings(for: device)
                    vault.savePairing(pairing, configuration: device, baseSettings: settings)
                    saveVault(vault)
                    await handler.close()
                    pairingHandler = nil
                    isPairing = false
                    isPairingReady = false
                    pairingPrompt = nil
                    status = "Paired. Click Connect."
                } catch {
                    isPairingReady = true
                    status = "Pairing failed: \(error.localizedDescription)"
                    DiagnosticsStore.shared.note("appletv.pair.failed", detail: error.localizedDescription)
                }
        }
    }

    func send(_ command: RemoteCommand) {
        guard let connected else {
            status = "Connect to an Apple TV first"
            return
        }
        Task {
            do {
                try await command.perform(on: connected.remoteControl)
                status = "Connected to \(selectedDevice?.name ?? "Apple TV")"
            } catch {
                status = "Command failed: \(error.localizedDescription)"
                DiagnosticsStore.shared.note("appletv.command.failed", detail: error.localizedDescription)
            }
        }
    }

    enum RemoteCommand {
        case up, down, left, right, select, menu, home, playPause, volumeUp, volumeDown

        func perform(on remote: any RemoteControl) async throws {
            switch self {
            case .up: try await remote.up()
            case .down: try await remote.down()
            case .left: try await remote.left()
            case .right: try await remote.right()
            case .select: try await remote.select()
            case .menu: try await remote.menu()
            case .home: try await remote.home()
            case .playPause: try await remote.playPause()
            case .volumeUp: try await remote.volumeUp()
            case .volumeDown: try await remote.volumeDown()
            }
        }
    }

    private func loadVault() -> ATVSettingsVault {
        guard let data = Keychain.load(),
              let vault = try? JSONDecoder().decode(ATVSettingsVault.self, from: data)
        else { return ATVSettingsVault() }
        return vault
    }

    private func saveVault(_ vault: ATVSettingsVault) {
        guard let data = try? JSONEncoder().encode(vault) else { return }
        Keychain.save(data)
    }
}

private extension DeviceModel {
    var isAppleTV: Bool {
        switch self {
        case .gen1, .gen2, .gen3, .gen4, .gen4K, .gen4K2, .gen4K3:
            return true
        default:
            return false
        }
    }
}

private enum Keychain {
    private static let service = "com.example.mxuslides.appletv"
    private static let account = "pairings"

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
