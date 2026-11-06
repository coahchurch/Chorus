import PresenterCore
import SwiftUI

struct ReflowSheet: View {
    private let model: SlideEditorModel?
    private let onImport: ((String, String, String, Int) -> Void)?
    private let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var transliteration = ""
    @State private var songName = ""
    @State private var linesPerSlide = 2
    @State private var showingReplacementWarning = false

    init(model: SlideEditorModel) {
        self.model = model
        onImport = nil
        onCancel = nil
    }

    init(
        importingSongNamed name: String,
        primaryText: String = "",
        transliteration: String = "",
        initialPairsPerSlide: Int = 2,
        onCancel: @escaping () -> Void,
        onImport: @escaping (String, String, String, Int) -> Void
    ) {
        model = nil
        self.onImport = onImport
        self.onCancel = onCancel
        _songName = State(initialValue:
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Song" : name
        )
        _text = State(initialValue: primaryText)
        _transliteration = State(initialValue: transliteration)
        _linesPerSlide = State(initialValue: min(max(initialPairsPerSlide, 1), 8))
    }

    var body: some View {
        let isSong = model.map { $0.presentation.presentationKind == .song } ?? true
        let parsed = isSong
            ? Reflow.parsePaired(text, transliteration: transliteration, linesPerSlide: linesPerSlide)
            : Reflow.parse(text, linesPerSlide: linesPerSlide)
        VStack(spacing: 0) {
            HStack {
                Text("Reflow")
                    .font(.headline)
                if model == nil {
                    TextField("Song name", text: $songName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
                Spacer()
                Text(isSong
                    ? "Keep matching lyric rows on the same line in both columns."
                    : "Label lines (Verse 1, Chorus…) start sections; blank lines split slides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            HSplitView {
                if isSong {
                    HStack(spacing: 1) {
                        lyricEditor("Original lyrics", text: $text)
                        Divider()
                        lyricEditor("Transliteration", text: $transliteration)
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                }
                preview(parsed)
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 14) {
                Stepper(
                    "\(isSong ? "Pairs" : "Lines") per slide: \(linesPerSlide)",
                    value: $linesPerSlide, in: 1...8
                )
                    .fixedSize()
                Spacer()
                Text(summary(parsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if model != nil, isSong {
                        showingReplacementWarning = true
                    } else {
                        applyReflow()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed.sections.allSatisfy(\.slides.isEmpty))
            }
            .padding(10)
        }
        .frame(minWidth: 820, minHeight: 460)
        .confirmationDialog(
            "Replace Manual Slide Edits?",
            isPresented: $showingReplacementWarning,
            titleVisibility: .visible
        ) {
            Button("Replace Slides", role: .destructive) { applyReflow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reflow will regenerate every slide from these lyric columns. Any manual slide edits will be replaced.")
        }
        .onAppear {
            if let model {
                text = model.reflowSeedText
                transliteration = model.presentation.transliterationSource ?? ""
            }
        }
    }

    private func lyricEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyReflow() {
        if let model {
            model.applyReflow(text: text, transliteration: transliteration, linesPerSlide: linesPerSlide)
            dismiss()
        } else {
            let name = songName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Song" : songName
            onImport?(name, text, transliteration, linesPerSlide)
            dismiss()
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func summary(_ parsed: Reflow.ParseResult) -> String {
        let slideCount = parsed.order.reduce(0) { $0 + parsed.sections[$1].slides.count }
        return "\(parsed.sections.count) sections · \(slideCount) slides"
    }

    private func preview(_ parsed: Reflow.ParseResult) -> some View {
        ReflowPreview(parsed: parsed, emptyTitle: "Paste Lyrics or Notes", emptyDescription: "Slides appear here as you type.")
    }
}

struct ReflowPreview: View {
    let parsed: Reflow.ParseResult
    var emptyTitle = "No Lyrics"
    var emptyDescription = ""

    var arrangementNames: [String]? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parsed.sections.enumerated()), id: \.offset) { sectionIndex, section in
                    Text(section.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, sectionIndex == 0 ? 0 : 8)
                    if section.slides.isEmpty {
                        Text("Empty section")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(section.slides.enumerated()), id: \.offset) { _, slide in

                        Text(ChordMath.extract(slide).text)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: CornerStandard.element, style: .continuous))
                    }
                }
                if let order = arrangementNames ?? (hasRepeats ? parsed.order.map { parsed.sections[$0].name } : nil) {
                    Text("Arrangement")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Text(order.joined(separator: " → "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if parsed.sections.isEmpty {
                ContentUnavailableView(
                    emptyTitle, systemImage: "text.alignleft",
                    description: Text(emptyDescription)
                )
            }
        }
    }

    private var hasRepeats: Bool {
        parsed.order.count != Set(parsed.order).count
    }
}
