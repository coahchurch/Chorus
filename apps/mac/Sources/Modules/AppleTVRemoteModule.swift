import SwiftUI

struct AppleTVRemoteModule: View {
    let remote: AppleTVRemoteController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Apple TV Remote")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Scan") { remote.scan() }
                    .buttonStyle(.borderless)
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
                Button("Connect") { remote.connect() }
                Text(remote.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(spacing: 6) {
                Button { remote.send(.up) } label: { Image(systemName: "chevron.up") }
                HStack(spacing: 18) {
                    Button { remote.send(.left) } label: { Image(systemName: "chevron.left") }
                    Button { remote.send(.select) } label: { Image(systemName: "circle") }
                    Button { remote.send(.right) } label: { Image(systemName: "chevron.right") }
                }
                Button { remote.send(.down) } label: { Image(systemName: "chevron.down") }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            HStack {
                Button("Menu") { remote.send(.menu) }
                Button("Home") { remote.send(.home) }
                Button { remote.send(.playPause) } label: { Image(systemName: "playpause") }
                Button { remote.send(.volumeDown) } label: { Image(systemName: "speaker.wave.1") }
                Button { remote.send(.volumeUp) } label: { Image(systemName: "speaker.wave.3") }
            }
            .buttonStyle(.borderless)
        }
    }
}
