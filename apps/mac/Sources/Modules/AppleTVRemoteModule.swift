import SwiftUI

struct AppleTVRemoteModule: View {
    let remote: AppleTVRemoteController
    @State private var pin = ""
    @AppStorage("app.accentColor") private var accentColorRaw = "indigo"

    private var accentColor: Color {
        switch accentColorRaw {
        case "blue": .blue
        case "green": .green
        case "orange": .orange
        default: .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Apple TV Remote")
                        .font(.headline)
                Spacer()
                    Button {
                        remote.scan()
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(remote.isScanning)
            }
            Picker("Apple TV", selection: Binding(
                get: { remote.selectedID ?? "" },
                set: { remote.selectedID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Select a device").tag("")
                ForEach(remote.devices, id: \.mainIdentifier) { device in
                    Text(device.name).tag(device.mainIdentifier ?? "")
                }
            }
            HStack {
                Button {
                    remote.connect()
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    remote.pair()
                } label: {
                    Label("Pair", systemImage: "lock")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(remote.isPairing || remote.hasSavedPairing)
                Text(remote.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if remote.isPairing {
                Text(remote.pairingPrompt ?? "Waiting for pairing...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("4-digit PIN", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .controlSize(.large)
                    .onChange(of: pin) { _, value in
                        pin = String(value.filter(\.isNumber).prefix(4))
                    }
                    Button("Submit") {
                    remote.submitPIN(pin)
                    if remote.isPairingReady {
                        pin = ""
                    }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!remote.isPairingReady || pin.filter(\.isNumber).count != 4)
                }
            }
            VStack(spacing: 12) {
                remoteButton(.up, systemImage: "chevron.up")
                HStack(spacing: 18) {
                    remoteButton(.left, systemImage: "chevron.left")
                    remoteButton(.select, systemImage: "circle", prominent: true)
                    remoteButton(.right, systemImage: "chevron.right")
                }
                remoteButton(.down, systemImage: "chevron.down")
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                remoteLabelButton("Menu", .menu)
                remoteLabelButton("Home", .home)
                remoteButton(.playPause, systemImage: "playpause")
                remoteButton(.volumeDown, systemImage: "speaker.wave.1")
                remoteButton(.volumeUp, systemImage: "speaker.wave.3")
            }
            .frame(maxWidth: .infinity)
        }
        .tint(accentColor)
    }

    private func remoteButton(
        _ command: AppleTVRemoteController.RemoteCommand,
        systemImage: String,
        prominent: Bool = false
    ) -> some View {
        Button {
            remote.send(command)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(accentColor.opacity(prominent ? 0.9 : 0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? .white : accentColor)
        .accessibilityLabel(Text(systemImage))
    }

    private func remoteLabelButton(
        _ title: String,
        _ command: AppleTVRemoteController.RemoteCommand
    ) -> some View {
        Button(title) {
            remote.send(command)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(accentColor)
        .frame(minWidth: 72, minHeight: 44)
        .background(Capsule().fill(accentColor.opacity(0.18)))
    }
}
