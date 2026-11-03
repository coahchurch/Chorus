import OutputEngine
import PresenterCore
import RenderEngine
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    let render: RenderContext?

    let close: () -> Void

    @State private var flow: OnboardingFlow

    @Environment(\.openWindow) private var openWindow

    init(
        model: AppModel, render: RenderContext?, close: @escaping () -> Void
    ) {
        self.model = model
        self.render = render
        self.close = close
        _flow = State(initialValue: OnboardingFlow(firstRun: model.needsOnboarding))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch flow.step {
                case .content: contentStep
                case .screens: screensStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            Divider()
            footer
        }
        .frame(width: 640)
        .frame(minHeight: 520)
        .interactiveDismissDisabled()
        .background(QuitDismissesSheet())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to Chorus")
                .font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                ForEach(OnboardingFlow.Step.allCases, id: \.self) { step in
                    HStack(spacing: 6) {
                        Text("\(step.rawValue + 1)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(step == flow.step ? Color.accentColor : Color.secondary.opacity(0.25)))
                            .foregroundStyle(step == flow.step ? Color.white : Color.secondary)
                        Text(step.title)
                            .font(.callout)
                            .foregroundStyle(step == flow.step ? .primary : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var contentStep: some View {
        contentChoices
    }

    private var contentChoices: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bring in your content")
                .font(.headline)
            Toggle("Include the Getting Started service and welcome presentation", isOn: $flow.includeGettingStarted)
                .font(.callout)
            Button {
                flow.choose(.startFromScratch)
            } label: {
                Text("Start From Scratch")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            Text("Opens on a short welcome presentation that walks through the basics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Moving from another Mac? Restore a library backup…") {
                BackupTransferRunner(model: model).presentImport()
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }

    private var screensStep: some View {
        let displays = render?.outputs.displays ?? []
        return VStack(alignment: .leading, spacing: 14) {
            Text("Pick your screens")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(displays) { display in
                    HStack {
                        Image(systemName: "display")
                        Text(display.name)
                        if display.isMain {
                            Text("This Mac's main display")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(display.frame.width))×\(Int(display.frame.height)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if displays.count > 1 {
                Text("Screen Configuration gives each display a role: Audience for the room, Confidence for the stage.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Only one display is connected, so nothing leaves this Mac yet — the Output Preview shows what the room would see. Connect a projector or TV any time and give it a role in Screen Configuration.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Screen Configuration…") { openWindow(id: "outputs") }
            Spacer(minLength: 0)
            Text("Camera, microphone and network access are asked for the first time a feature needs them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip Setup") { finish() }
                .buttonStyle(.link)
            Spacer()
            if flow.canGoBack {
                Button("Back") { flow.back() }
            }
            if flow.isLastStep {
                Button("Get Started") { finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { flow.advance() }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func finish() {
        model.finishOnboarding(includeGettingStarted: flow.includeGettingStarted)
        close()
    }
}

private struct QuitDismissesSheet: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.preventsApplicationTerminationWhenModal = false }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.preventsApplicationTerminationWhenModal = false }
    }
}

struct HelpCommands: Commands {
    let model: AppModel?
    @Binding var showWelcome: Bool
    @Binding var showFeedback: Bool

    @AppStorage(PresentLayoutController.lockedKey) private var runOnly = false

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Show Welcome") { showWelcome = true }
                .disabled(model == nil || runOnly)
            Button("Restore Getting Started") { model?.restoreGettingStarted() }
                .disabled(model == nil || runOnly)
            Divider()
            Button("Report a Problem…") { showFeedback = true }
        }
    }
}
