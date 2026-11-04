import SwiftUI

struct AirPlayReceiverModule: View {
    @ObservedObject var receiver: AirPlayReceiverController

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AirPlay Receiver")
                        .font(.title2.weight(.semibold))
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
            }

            if case .mirroring = receiver.state {
                VideoDisplayView(videoDecoder: receiver.manager.videoDecoder)
                    .frame(minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView(
                    "Waiting for a device",
                    systemImage: "airplayvideo",
                    description: Text("Start the receiver, then choose Chorus from Screen Mirroring on an iPhone or iPad.")
                )
                .frame(minHeight: 220)
            }

            HStack(spacing: 10) {
                Button(receiver.isRunning ? "Restart Receiver" : "Start Receiver") {
                    receiver.isRunning ? receiver.restart() : receiver.start()
                }
                .buttonStyle(.borderedProminent)

                if receiver.isRunning {
                    Button("Stop", role: .destructive) {
                        receiver.stop()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var statusText: String {
        switch receiver.state {
        case .idle: receiver.isRunning ? "Advertising and waiting for a device" : "Not advertising"
        case .connecting(let device): "Connecting to \(device)"
        case .mirroring(let device): "Mirroring from \(device)"
        case .error(let message): message
        }
    }

    private var statusColor: Color {
        switch receiver.state {
        case .mirroring: .green
        case .connecting: .orange
        case .error: .red
        case .idle: .secondary
        }
    }
}
