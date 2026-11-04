import AppKit
import CoreImage
import CoreVideo
import NDIKit
import OutputEngine
import PresenterCore
import RenderEngine
import SlideScene
import SwiftUI

struct LivePanel: View {
    let model: AppModel
    let render: RenderContext?
    let controls: ServiceControls?
    let layout: PresentLayoutController?
    @ObservedObject private var airPlayReceiver: AirPlayReceiverController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.runOnly) private var runOnly
    @Environment(\.confidenceMonitor) private var confidenceMonitor
    @State private var previewHovering = false

    @AppStorage("preview.mode") private var previewModeRaw = PreviewMode.audience.rawValue
    @AppStorage("preview.screenTarget") private var legacyPreviewTarget = ""
    @AppStorage("preview.audienceTarget") private var audienceTarget = ""
    @AppStorage("preview.stageTarget") private var stageTarget = ""
    @AppStorage("preview.ndiSource") private var selectedNDISource = ""
    @State private var ndiSources: [String] = []
    @State private var ndiInput: NDIInputSource?
    @State private var ndiFrame: NSImage?
    @State private var ndiError: String?

    init(
        model: AppModel,
        render: RenderContext?,
        controls: ServiceControls?,
        layout: PresentLayoutController?
    ) {
        self.model = model
        self.render = render
        self.controls = controls
        self.layout = layout
        self._airPlayReceiver = ObservedObject(
            wrappedValue: controls?.airPlayReceiver ?? AirPlayReceiverController())
    }

    private enum PreviewMode: String, CaseIterable, Identifiable {
        case audience
        case stage
        case liveStream

        var id: String { rawValue }
        var title: String {
            switch self {
            case .audience: "Audience"
            case .stage: "Stage"
            case .liveStream: "Live Stream"
            }
        }
    }

    private var previewMode: PreviewMode {
        PreviewMode(rawValue: previewModeRaw) ?? .audience
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Preview", selection: $previewModeRaw) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                previewContent
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 2)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarSectionHeader("Output Preview", glyph: .media) {
                previewToolbar
            }
        }
        .onDisappear { ndiInput?.stop() }
        .task(id: "\(previewModeRaw)::\(selectedNDISource)") {
            guard previewMode == .liveStream else { return }
            if ndiSources.isEmpty && ndiError == nil {
                refreshNDISources()
            }
            await receiveNDIPreview(source: selectedNDISource)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch previewMode {
        case .audience:
            outputPreview(
                role: .audience,
                stored: audienceTarget.isEmpty ? legacyPreviewTarget : audienceTarget)
        case .stage:
            outputPreview(role: .confidence, stored: stageTarget)
        case .liveStream:
            ndiPreview
        }
    }

    @ViewBuilder
    private func outputPreview(role: ScreenRole, stored: String) -> some View {
        if let render {
            let choices = targetChoices(render, role: role)
            let resolved = resolveTarget(stored, choices: choices)
            if let resolved {
                ZStack {
                    LiveSceneView(render: render, screenTargetID: resolved.id)
                    if role == .audience,
                       case .mirroring = airPlayReceiver.state {
                        VideoDisplayView(videoDecoder: airPlayReceiver.manager.videoDecoder)
                    }
                }
                .aspectRatio(
                    PreviewTargets.aspect(
                        of: resolved.id, render: render,
                        layoutAspects: confidenceMonitor?.previewAspects ?? [:]),
                    contentMode: .fit)
                    .modifier(PreviewedLayoutKeeper(target: resolved.id))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle.standard(CornerStandard.element))
                    .overlay {
                        RoundedRectangle.standard(CornerStandard.element)
                            .strokeBorder(Color.separator.opacity(0.6), lineWidth: 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if previewHovering, !runOnly {
                            Button {
                                popOutPreview(target: resolved.id)
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(4)
                                    .background(.black.opacity(0.45), in: RoundedRectangle.standard(CornerStandard.element))
                                    .padding(5)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open this output's preview in its own window")
                        }
                    }
                    .onHover { previewHovering = $0 }
                    .contextMenu {
                        if !runOnly {
                            Button("Open in Window") { popOutPreview(target: resolved.id) }
                            if choices.screens.count + choices.layouts.count > 1 {
                                Menu("Open Preview Window") {
                                    ForEach(choices.screens, id: \.id) { screen in
                                        Button(screen.name) {
                                            openWindow(id: "preview", value: screen.id)
                                        }
                                    }
                                    if !choices.layouts.isEmpty {
                                        Divider()
                                        ForEach(choices.layouts, id: \.id) { layout in
                                            Button(layout.name) {
                                                openWindow(id: "preview", value: layout.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    role == .audience ? "No Audience Output" : "No Stage Output",
                    systemImage: "display",
                    description: Text(role == .audience
                        ? "Connect or configure an audience screen to preview it here."
                        : "Assign a confidence screen or choose a stage layout to preview it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        } else {
            ContentUnavailableView("Preview Unavailable", systemImage: "display")
        }
    }

    private var ndiPreview: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.black
                if let ndiFrame {
                    Image(nsImage: ndiFrame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24))
                        Text(ndiError ?? (selectedNDISource.isEmpty
                            ? "Choose an OBS NDI source to preview."
                            : "Waiting for the selected NDI source…"))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(16)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle.standard(CornerStandard.element))
            .overlay {
                RoundedRectangle.standard(CornerStandard.element)
                    .strokeBorder(Color.separator.opacity(0.6), lineWidth: 1)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(ndiStatus.hasPrefix("Receiving") ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(ndiStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Refresh Sources") { refreshNDISources() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var ndiStatus: String {
        guard let ndiInput else {
            return ndiError ?? (selectedNDISource.isEmpty ? "No source selected" : "Connecting")
        }
        return switch ndiInput.state {
        case .searching: "Searching for \(selectedNDISource)"
        case .receiving(let sourceName): "Receiving \(sourceName)"
        case .offline: "Source offline: \(selectedNDISource)"
        }
    }

    @ViewBuilder
    private var previewToolbar: some View {
        switch previewMode {
        case .audience:
            outputPicker(
                role: .audience,
                stored: audienceTarget.isEmpty ? legacyPreviewTarget : audienceTarget)
        case .stage:
            outputPicker(role: .confidence, stored: stageTarget)
        case .liveStream:
            ndiSourcePicker
        }
    }

    @ViewBuilder
    private func outputPicker(role: ScreenRole, stored: String) -> some View {
        if let render {
            let choices = targetChoices(render, role: role)
            let resolved = resolveTarget(stored, choices: choices)
            Menu {
                if !choices.screens.isEmpty {
                    Section(role == .audience ? "Audience Screens" : "Stage Screens") {
                        ForEach(choices.screens, id: \.id) { screen in
                            Toggle(screen.name, isOn: Binding(
                                get: { resolved?.id == screen.id },
                                set: { _ in setTarget(screen.id, role: role) }
                            ))
                        }
                    }
                }
                if !choices.layouts.isEmpty {
                    Section("Stage Layouts") {
                        ForEach(choices.layouts, id: \.id) { layout in
                            Toggle(layout.name, isOn: Binding(
                                get: { resolved?.id == layout.id },
                                set: { _ in setTarget(layout.id, role: role) }
                            ))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(resolved?.name ?? "No Outputs")
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .headerItemBackground()
            .help("Choose the output shown in this preview")
            .disabled(choices.screens.isEmpty && choices.layouts.isEmpty)
        }
    }

    private func targetChoices(
        _ render: RenderContext, role: ScreenRole
    ) -> (screens: [PreviewTargetLogic.Choice], layouts: [PreviewTargetLogic.Choice]) {
        let screens = PreviewTargets.screens(render).compactMap { screen -> PreviewTargetLogic.Choice? in
            if screen.id == NDIScreenOutputs.shared.lowerThirdScreenID?.uuidString {
                return nil
            }
            if let id = UUID(uuidString: screen.id), render.outputs.role(forScreen: id) != role {
                return nil
            }
            return PreviewTargetLogic.Choice(id: screen.id, name: screen.name)
        }
        let layouts = role == .confidence ? confidenceMonitor?.previewLayoutChoices ?? [] : []
        return (screens, layouts)
    }

    private func resolveTarget(
        _ stored: String,
        choices: (screens: [PreviewTargetLogic.Choice], layouts: [PreviewTargetLogic.Choice])
    ) -> PreviewTargetLogic.Choice? {
        PreviewTargetLogic.resolve(stored: stored, screens: choices.screens, layouts: choices.layouts)
    }

    private func popOutPreview(target: String) {
        guard !target.isEmpty else { return }
        openWindow(id: "preview", value: target)
    }

    private func setTarget(_ target: String, role: ScreenRole) {
        switch role {
        case .audience:
            audienceTarget = target
            legacyPreviewTarget = target
        case .confidence:
            stageTarget = target
        case .liveStream:
            audienceTarget = target
        }
    }

    private var ndiSourcePicker: some View {
        Menu {
            Button("Refresh Sources") { refreshNDISources() }
            if ndiSources.isEmpty {
                Divider()
                Text(ndiError ?? "No NDI sources found")
            } else {
                Divider()
                ForEach(ndiSources, id: \.self) { source in
                    Button {
                        selectedNDISource = source
                    } label: {
                        if selectedNDISource == source {
                            Label(source, systemImage: "checkmark")
                        } else {
                            Text(source)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedNDISource.isEmpty ? "Select NDI" : selectedNDISource)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .headerItemBackground()
        .help("Choose an NDI input, such as the OBS program output")
    }

    @MainActor
    private func refreshNDISources() {
        Task {
            let result = await Task.detached(priority: .utility) { () -> (sources: [String]?, error: String?) in
                do {
                    let library = try NDILibrary.load()
                    guard let finder = NDIFinder(library: library) else {
                        return (nil, "NDI source discovery could not start.")
                    }
                    return (finder.currentSourceNames(wait: 1200), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            if let sources = result.sources {
                ndiSources = sources
                ndiError = nil
                if !selectedNDISource.isEmpty, !sources.contains(selectedNDISource) {
                    ndiError = "The selected source is not currently available."
                }
            } else {
                ndiError = result.error ?? "NDI source discovery failed."
            }
        }
    }

    @MainActor
    private func receiveNDIPreview(source: String) async {
        ndiInput?.stop()
        ndiInput = nil
        ndiFrame = nil
        ndiError = nil
        guard !source.isEmpty else { return }

        do {
            let input = NDIInputSource(
                library: try NDILibrary.load(), sourceNameContaining: source)
            ndiInput = input
            defer {
                input.stop()
                if ndiInput === input { ndiInput = nil }
            }
            while !Task.isCancelled {
                if let pixelBuffer = input.latestFrame() {
                    let transferable = SendableNDIPixelBuffer(pixelBuffer)
                    let frame = await Task.detached(priority: .utility) {
                        NDIFrameRenderer.render(transferable.value)
                    }.value
                    if !Task.isCancelled, let frame {
                        ndiFrame = NSImage(
                            cgImage: frame.image,
                            size: NSSize(width: frame.image.width, height: frame.image.height))
                    }
                }
                try await Task.sleep(for: .milliseconds(90))
            }
        } catch is CancellationError {
        } catch {
            ndiError = error.localizedDescription
        }
    }

    private struct SendableNDIPixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
        init(_ value: CVPixelBuffer) { self.value = value }
    }

    private struct NDIFrameSnapshot: @unchecked Sendable {
        let image: CGImage
    }

    private final class NDIFrameRenderer: @unchecked Sendable {
        static let shared = NDIFrameRenderer()
        private let context = CIContext()

        private init() {}

        static func render(_ buffer: CVPixelBuffer) -> NDIFrameSnapshot? {
            let image = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = shared.context.createCGImage(image, from: image.extent) else {
                return nil
            }
            return NDIFrameSnapshot(image: cgImage)
        }
    }
}

struct LiveSceneView: NSViewRepresentable {
    let render: RenderContext

    var screenTargetID: String?

    init(render: RenderContext, screenTargetID: String? = nil) {
        self.render = render
        self.screenTargetID = screenTargetID
    }

    func makeNSView(context: Context) -> MetalSceneView {
        let view = MetalSceneView(compositor: render.compositor)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: MetalSceneView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: MetalSceneView) {
        if let screenTargetID {
            view.sceneProvider = render.previewProvider(for: screenTargetID)
        } else {
            view.sceneProvider = { [transitions = render.transitions] in
                transitions.scene(at: Date())
            }
        }
    }
}

struct AudioTransportControls<Trailing: View>: View {
    let model: AppModel
    let player: AudioPlayer
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let livePlaylist = player.playlistID.flatMap { try? model.playlist($0) }
        HStack(spacing: 6) {
            TransportIconButton(symbol: "backward.fill", help: "Previous — restarts past 3s") {
                player.previous()
            }
            TransportIconButton(
                symbol: player.isPlaying ? "pause.fill" : "play.fill",
                help: player.isPlaying ? "Pause" : "Play"
            ) {
                player.togglePlayPause()
            }
            TransportIconButton(symbol: "forward.fill", help: "Next") {
                player.next()
            }
            if let livePlaylist {
                Divider().frame(height: 14)
                let shuffled = livePlaylist.shuffle ?? false
                TransportIconButton(
                    symbol: "shuffle", help: shuffled ? "Shuffle off" : "Shuffle",
                    active: shuffled
                ) {
                    model.updatePlaylist(livePlaylist.id) { $0.shuffle = !shuffled }
                    player.refreshFromDocument()
                }
                let mode = livePlaylist.playbackMode
                TransportIconButton(
                    symbol: mode == .loopSingle ? "repeat.1" : "repeat",
                    help: Self.repeatHelp(mode),
                    active: mode != .playAll
                ) {
                    model.updatePlaylist(livePlaylist.id) {
                        $0.playbackMode = Self.nextRepeatMode(mode)
                    }
                    player.refreshFromDocument()
                }
            }
            Spacer(minLength: 6)
            trailing()
        }
    }

    private static func nextRepeatMode(_ mode: PlaybackMode) -> PlaybackMode {
        switch mode {
        case .playAll: .loopPlaylist
        case .loopPlaylist: .loopSingle
        case .loopSingle: .playAll
        }
    }

    private static func repeatHelp(_ mode: PlaybackMode) -> String {
        switch mode {
        case .playAll: "Repeat off — click for Loop Playlist"
        case .loopPlaylist: "Loop Playlist — click for Loop Single"
        case .loopSingle: "Loop Single — click for repeat off"
        }
    }
}

struct TransportIconButton: View {
    let symbol: String
    let help: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(active ? Color.green : .secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(active ? 0.10 : 0.05),
            in: RoundedRectangle.standard(CornerStandard.element)
        )
        .help(help)
    }
}

extension Color {
    static var separator: Color { Color(nsColor: .separatorColor) }
}

@MainActor
enum PreviewTargets {
    static func screens(_ render: RenderContext) -> [(id: String, name: String)] {
        let outputs = render.outputs
        return outputs.placeholderScreens.map { ($0.id.uuidString, $0.name) }
            + outputs.displays.map { ($0.uuid, $0.name) }
    }

    static func resolve(
        _ stored: String, render: RenderContext,
        layouts: [PreviewTargetLogic.Choice] = []
    ) -> (id: String, name: String)? {
        PreviewTargetLogic.resolve(
            stored: stored,
            screens: screens(render).map { .init(id: $0.id, name: $0.name) },
            layouts: layouts
        ).map { ($0.id, $0.name) }
    }

    static func aspect(
        of targetID: String?, render: RenderContext,
        layoutAspects: [String: Double] = [:]
    ) -> CGFloat {
        guard let targetID else { return 16 / 9 }
        if let layoutID = PreviewTargetLogic.layoutID(for: targetID) {
            return CGFloat(layoutAspects[layoutID] ?? 16 / 9)
        }
        let outputs = render.outputs
        if let uuid = UUID(uuidString: targetID),
           let placeholder = outputs.placeholderScreens.first(where: { $0.id == uuid }),
           placeholder.height > 0 {
            return CGFloat(placeholder.width) / CGFloat(placeholder.height)
        }
        if let display = outputs.displays.first(where: { $0.uuid == targetID }),
           display.frame.height > 0 {
            return display.frame.width / display.frame.height
        }
        return 16 / 9
    }
}

struct PreviewedLayoutKeeper: ViewModifier {
    let target: String?
    @Environment(\.confidenceMonitor) private var confidenceMonitor

    private var layoutID: String? {
        target.flatMap(PreviewTargetLogic.layoutID)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { begin(layoutID) }
            .onDisappear { end(layoutID) }
            .onChange(of: layoutID) { old, new in
                end(old)
                begin(new)
            }
    }

    private func begin(_ layoutID: String?) {
        if let layoutID {
            confidenceMonitor?.beginPreview(layoutID: layoutID)
        }
    }

    private func end(_ layoutID: String?) {
        if let layoutID {
            confidenceMonitor?.endPreview(layoutID: layoutID)
        }
    }
}
