import SwiftATV
import Observation

@MainActor
@Observable
final class AppleTVRemoteController {
    private(set) var devices: [AppleTVConfiguration] = []
    private(set) var status = "Not connected"
    private(set) var isScanning = false
    private var connected: (any AppleTVDevice)?
    var selectedID: String?

    var selectedDevice: AppleTVConfiguration? {
        devices.first { $0.mainIdentifier == selectedID }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        status = "Scanning for Apple TVs..."
        Task {
            defer { isScanning = false }
            do {
                let found = try await ATVClient.scan(timeout: 5)
                devices = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if selectedID == nil { selectedID = devices.first?.mainIdentifier }
                status = devices.isEmpty ? "No Apple TVs found" : "\(devices.count) device\(devices.count == 1 ? "" : "s") found"
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
        Task {
            do {
                connected = try await ATVClient.connect(device).device
                status = "Connected to \(device.name)"
            } catch {
                connected = nil
                status = "Connection failed: \(error.localizedDescription)"
                DiagnosticsStore.shared.note("appletv.connect.failed", detail: error.localizedDescription)
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
}
