import AppKit
import PresenterCore
import SwiftUI

@MainActor
@Observable
final class ImportActivityModel {
    var title: String
    var phase = "Preparing…"
    var detail = ""
    var completed = 0
    var total: Int?
    var finished = false
    var summaryLines: [String] = []
    var warnings: [String] = []

    var backupOptionsRequest: BackupOptionsRequest?

    var finishedHeadline = "Import finished"
    var emptyHeadline = "Nothing was imported."

    init(title: String) {
        self.title = title
    }

    func requestBackupOptions(
        scan: BackupScan, options: BackupImportOptions,
        respond: @escaping (BackupImportOptions?) -> Void
    ) {
        backupOptionsRequest = BackupOptionsRequest(
            scan: scan, options: options, respond: respond)
    }

    func apply(_ progress: BackupProgress) {
        phase = progress.phase
        detail = progress.detail
        completed = progress.completed
        total = progress.total
    }

    func finish(summaryLines: [String], warnings: [String]) {
        self.summaryLines = summaryLines
        self.warnings = warnings
        finished = true
    }
}

@MainActor
enum ImportActivityWindow {
    private static var window: NSWindow?

    static func present(_ model: ImportActivityModel) {
        window?.close()
        let hosting = NSHostingController(rootView: ImportActivityView(model: model) {
            window?.close()
            window = nil
        })
        let panel = NSWindow(contentViewController: hosting)
        panel.title = model.title
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    static func dismiss() {
        window?.close()
        window = nil
    }
}

struct BackupOptionsRequest {
    let scan: BackupScan
    let options: BackupImportOptions
    let respond: (BackupImportOptions?) -> Void
}

struct ImportActivityView: View {
    let model: ImportActivityModel
    let close: () -> Void
    @State private var warningsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let request = model.backupOptionsRequest {
                BackupOptionsView(request: request) { model.backupOptionsRequest = nil }
            } else if model.finished {
                results
            } else {
                progress
            }
        }
        .padding(16)
        .frame(width: model.backupOptionsRequest == nil ? 440 : 560)
    }

    @ViewBuilder
    private var progress: some View {
        Text(model.phase)
            .font(.headline)
        if let total = model.total, total > 0 {
            ProgressView(value: Double(min(model.completed, total)), total: Double(total))
            Text("\(model.completed + 1) of \(total)\(model.detail.isEmpty ? "" : " — \(model.detail)")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        Text(model.summaryLines.isEmpty ? model.emptyHeadline : model.finishedHeadline)
            .font(.headline)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(model.summaryLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.callout)
            }
        }
        if !model.warnings.isEmpty {

            DisclosureGroup(
                "\(model.warnings.count) warning\(model.warnings.count == 1 ? "" : "s")",
                isExpanded: $warningsExpanded
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }
            .font(.callout)

            .onAppear { warningsExpanded = model.summaryLines.isEmpty }
        }
        HStack {
            Spacer()
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct BackupOptionsView: View {
    let request: BackupOptionsRequest
    let dismissStep: () -> Void
    @State private var options: BackupImportOptions

    init(request: BackupOptionsRequest, dismissStep: @escaping () -> Void) {
        self.request = request
        self.dismissStep = dismissStep
        _options = State(initialValue: request.options)
    }

    var body: some View {
        Text("Choose what to import")
            .font(.headline)
        Text("Backup from \(request.scan.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 28) {
            column("Content", .content)
            column("Setup", .setup)
        }
        Divider()
        Picker("If something here already exists:", selection: $options.policy) {
            ForEach(BackupConflictPolicy.allCases, id: \.self) { policy in
                Text(policy.displayName).tag(policy)
            }
        }
        .pickerStyle(.radioGroup)
        Text("“Merge” never loses an edit, so it can't undo one either — to go back to the backup's version of something, choose “Replace”. App settings apply the next time Chorus opens. Nothing here ever changes what's live on your outputs.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Cancel") {
                dismissStep()
                request.respond(nil)
            }
            .keyboardShortcut(.cancelAction)
            Button("Import") {
                dismissStep()
                request.respond(options)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func column(_ title: String, _ column: BackupSection.Column) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ImportOptionsColumnHeader(title: title)
            ForEach(BackupSection.allCases.filter { $0.column == column }, id: \.self) { section in
                if section != .mediaFiles || options.includes(.media) {
                    ImportOptionRow(
                        title: section.title, count: request.scan.count(section),
                        isOn: binding(section))
                        .padding(.leading, section == .mediaFiles ? 18 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ section: BackupSection) -> Binding<Bool> {
        Binding(
            get: { !options.excluded.contains(section) },
            set: { isOn in
                if isOn {
                    options.excluded.remove(section)
                } else {
                    options.excluded.insert(section)
                }
            })
    }
}

private struct ImportOptionsColumnHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ImportOptionRow: View {
    let title: String
    let count: Int?
    @Binding var isOn: Bool

    var body: some View {
        if count == nil || count! > 0 {
            Toggle(isOn: $isOn) {
                HStack(spacing: 5) {
                    Text(title)
                    if let count {
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .toggleStyle(.checkbox)
        }
    }
}
