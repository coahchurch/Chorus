import AVKit
import Observation
import OutputEngine
import PresenterCore
import RenderEngine
import StreamEngine
import SwiftUI

enum AirPlayOutputRole: String, CaseIterable, Identifiable {
    case audience
    case stage

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var defaultsKey: String { "airplay.\(rawValue).receiver" }
}

@MainActor
@Observable
final class AirPlayOutputController {
    private static let enabledKey = "airplay.enabledRoles"
    struct Route: Identifiable {
        let role: AirPlayOutputRole
        var player: AVPlayer?
        var url: URL?
        var mirror: OutputMirror?
        var broadcaster: LocalHLSBroadcaster?
        var id: String { role.rawValue }
    }

    private(set) var routes: [AirPlayOutputRole: Route] = [:]
    private unowned let render: RenderContext

    init(render: RenderContext) {
        self.render = render
    }

    func restoreEnabledRoutes() {
        let roles = UserDefaults.standard.stringArray(forKey: Self.enabledKey) ?? []
        for raw in roles {
            if let role = AirPlayOutputRole(rawValue: raw) {
                start(role)
            }
        }
    }

    func start(_ role: AirPlayOutputRole) {
        guard routes[role] == nil else {
            routes[role]?.player?.play()
            return
        }
        persistEnabledRoutes(including: role)
        let size = size(for: role)
        let video = StreamVideoConfiguration(
            width: size.width, height: size.height, frameRate: 30,
            bitrateKbps: 6_000, codec: .h264, hdr: false)
        let broadcaster = LocalHLSBroadcaster(video: video)
        guard let mirror = OutputMirror(
            compositor: render.compositor,
            width: size.width, height: size.height,
            framesPerSecond: 30,
            provider: provider(for: role),
            sink: { [weak broadcaster] buffer, hostSeconds in
                broadcaster?.append(buffer, atHostSeconds: hostSeconds)
            }
        ) else { return }
        Task { [weak self] in
            do {
                try await broadcaster.start()
                guard let url = broadcaster.url, let self else { return }
                mirror.start()
                await broadcaster.waitForFirstSegment()
                let player = AVPlayer(url: url)
                player.allowsExternalPlayback = true
                player.play()
                self.routes[role] = Route(
                    role: role, player: player, url: url,
                    mirror: mirror, broadcaster: broadcaster)
            } catch {
                mirror.stop()
                await broadcaster.stop()
                DiagnosticsStore.shared.note(
                    "airplay.start.failed", detail: "\(role.rawValue): \(error.localizedDescription)")
            }
        }
    }

    func stop(_ role: AirPlayOutputRole) {
        guard let route = routes.removeValue(forKey: role) else { return }
        persistEnabledRoutes(removing: role)
        route.player?.pause()
        route.mirror?.stop()
        Task { await route.broadcaster?.stop() }
    }

    func player(for role: AirPlayOutputRole) -> AVPlayer? {
        routes[role]?.player
    }

    private func provider(for role: AirPlayOutputRole) -> @Sendable () -> RenderScene {
        switch role {
        case .audience:
            return render.outputs.sceneProvider ?? { .empty }
        case .stage:
            guard let screen = render.outputs.placeholderScreens.first(where: {
                render.outputs.role(forScreen: $0.id) == .confidence
            }) else {
                return { .empty }
            }
            return render.outputs.previewProvider(for: screen.id.uuidString)
        }
    }

    private func size(for role: AirPlayOutputRole) -> (width: Int, height: Int) {
        switch role {
        case .audience:
            return (1920, 1080)
        case .stage:
            let screen = render.outputs.placeholderScreens.first {
                render.outputs.role(forScreen: $0.id) == .confidence
            }
            return (screen?.width ?? 1920, screen?.height ?? 1080)
        }
    }

    private func persistEnabledRoutes(
        including role: AirPlayOutputRole? = nil,
        removing removedRole: AirPlayOutputRole? = nil
    ) {
        var roles = Set(routes.keys)
        if let role { roles.insert(role) }
        if let removedRole { roles.remove(removedRole) }
        UserDefaults.standard.set(
            roles.map(\.rawValue).sorted(), forKey: Self.enabledKey)
    }
}

struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}

struct AirPlayOutputsPanel: View {
    @Bindable var controller: AirPlayOutputController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIRPLAY OUTPUTS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            ForEach(AirPlayOutputRole.allCases) { role in
                HStack {
                    Text(role.title)
                        .font(.caption)
                    Spacer()
                    if let player = controller.player(for: role) {
                        AirPlayRoutePicker(player: player)
                            .frame(width: 28, height: 24)
                        Button("Stop") { controller.stop(role) }
                    } else {
                        Button("Start") { controller.start(role) }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.cardSurface, in: RoundedRectangle.standard(CornerStandard.element))
    }
}
