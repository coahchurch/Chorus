import AppKit
import PresenterCore
import SwiftUI

struct SongEditorView: View {
    let model: AppModel
    let songID: String

    @State private var draft: SongLyrics?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let draft {
                editor(draft)
            } else if let loadError {
                ContentUnavailableView(
                    "Song Unavailable",
                    systemImage: "music.note",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading song…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: songID) {
            draft = await model.loadSong(songID)
            loadError = draft == nil
                ? model.songLoadErrors[songID] ?? "The song could not be loaded."
                : nil
        }
        .alert("Unable to Save Song", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The song could not be saved.")
        }
    }

    private func editor(_ song: SongLyrics) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    TextField("Song name", text: binding(\.name))
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                    Spacer()
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .disabled(isSaving)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(16)
                Divider()
                if geometry.size.width < 720 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            songDetails(song, compact: geometry.size.width < 520)
                            Divider()
                            preview(song)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            songDetails(song, compact: false)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        preview(song)
                            .frame(width: 300)
                    }
                }
            }
        }
    }

    private func songDetails(_ song: SongLyrics, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if compact {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        TextField("Author", text: binding(\.author))
                        TextField("Copyright", text: binding(\.copyright))
                    }
                    HStack(spacing: 12) {
                        TextField("Primary language", text: binding(\.primaryLanguage))
                        TextField("Key", text: binding(\.key))
                    }
                    HStack(spacing: 12) {
                        tempoField
                        ccliField
                    }
                }
            } else {
                HStack(spacing: 12) {
                    TextField("Author", text: binding(\.author))
                    TextField("Copyright", text: binding(\.copyright))
                }
                HStack(spacing: 12) {
                    TextField("Primary language", text: binding(\.primaryLanguage))
                    TextField("Key", text: binding(\.key))
                    tempoField.frame(width: 80)
                    ccliField.frame(width: 80)
                }
            }
            ForEach(Array(song.parts.indices), id: \.self) { index in
                partEditor(index)
            }
            Button {
                appendPart()
            } label: {
                Label("Add Verse or Chorus", systemImage: "plus")
            }
        }
    }

    private var tempoField: some View {
        TextField("Tempo", text: Binding(
            get: { draft?.tempo.map { String($0) } ?? "" },
            set: { draft?.tempo = Double($0) }
        ))
    }

    private var ccliField: some View {
        TextField("CCLI", text: Binding(
            get: { draft?.ccliNumber.map(String.init) ?? "" },
            set: { draft?.ccliNumber = Int($0) }
        ))
    }

    private func partEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Verse label", text: partBinding(index, \.label))
                    .font(.headline)
                    .textFieldStyle(.plain)
                Spacer()
                Button(role: .destructive) {
                    removePart(index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Remove this part")
            }
            if let part = draft?.parts[safe: index],
               !part.transliterationLines.isEmpty,
               part.transliterationLines.count != part.primaryLines.count {
                Label("Line counts differ; align corresponding translations by row.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 10) {
                lyricColumn(
                    title: "Original lyrics",
                    text: linesBinding(index, transliteration: false),
                    onPasteBlock: { text in splitPastedLyrics(text, at: index) }
                )
                lyricColumn(
                    title: "Transliteration",
                    text: linesBinding(index, transliteration: true)
                )
            }
        }
        .padding(12)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func lyricColumn(
        title: String,
        text: Binding<String>,
        onPasteBlock: ((String) -> Bool)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            SongLinesTextEditor(text: text, onPasteBlock: onPasteBlock)
                .frame(height: lyricEditorHeight(text.wrappedValue))
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func lyricEditorHeight(_ text: String) -> CGFloat {
        let lines = max(2, text.components(separatedBy: .newlines).count)
        return min(420, CGFloat(lines * 21 + 18))
    }

    private func preview(_ song: SongLyrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Slide Preview")
                .font(.headline)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(song.presentation().slides.enumerated()), id: \.offset) { _, slide in
                        let text = slide.objects.map(\.text)
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        Text(text.isEmpty ? " " : text)
                            .font(.system(size: 15, weight: .medium))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 105)
                            .background(.black, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.basePlane)
    }

    private func binding(_ keyPath: WritableKeyPath<SongLyrics, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var current = draft else { return }
                current[keyPath: keyPath] = value
                draft = current
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<SongLyrics, String?>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var current = draft else { return }
                current[keyPath: keyPath] = value.isEmpty ? nil : value
                draft = current
            }
        )
    }

    private func partBinding(
        _ index: Int, _ keyPath: WritableKeyPath<SongLyricsPart, String>
    ) -> Binding<String> {
        Binding(
            get: { draft?.parts[safe: index]?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var current = draft, current.parts.indices.contains(index) else { return }
                current.parts[index][keyPath: keyPath] = value
                draft = current
            }
        )
    }

    private func linesBinding(_ index: Int, transliteration: Bool) -> Binding<String> {
        Binding(
            get: {
                guard let part = draft?.parts[safe: index] else { return "" }
                return (transliteration ? part.transliterationLines : part.primaryLines)
                    .joined(separator: "\n")
            },
            set: { text in
                guard var current = draft, current.parts.indices.contains(index) else { return }
                let lines = text.components(separatedBy: .newlines)
                if transliteration {
                    current.parts[index].transliterationLines = lines
                } else {
                    current.parts[index].primaryLines = lines
                }
                draft = current
            }
        )
    }

    private func splitPastedLyrics(_ text: String, at index: Int) -> Bool {
        let pastedParts = SongLyrics.pasted(name: "", primaryText: text).parts
        guard pastedParts.count > 1,
              var current = draft,
              current.parts.indices.contains(index)
        else { return false }

        if current.parts[index].primaryLines.isEmpty {
            current.parts[index].label = pastedParts[0].label
        }
        current.parts[index].primaryLines = pastedParts[0].primaryLines
        let followingParts = pastedParts.dropFirst().map {
            SongLyricsPart(label: $0.label, primaryLines: $0.primaryLines)
        }
        current.parts.insert(contentsOf: followingParts, at: index + 1)
        draft = current
        return true
    }

    private func appendPart() {
        guard var current = draft else { return }
        current.parts.append(SongLyricsPart(label: "Verse \(current.parts.count + 1)"))
        draft = current
    }

    private func removePart(_ index: Int) {
        guard var current = draft, current.parts.indices.contains(index) else { return }
        current.parts.remove(at: index)
        draft = current
    }

    private func save() {
        guard let draft else { return }
        isSaving = true
        let task = model.updateSong(songID) { $0 = draft }
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await task.value
                model.noteEditorSave(of: .song, id: songID, value: draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SongLinesTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onPasteBlock: ((String) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onPasteBlock: onPasteBlock)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.pasteBlock = { [weak coordinator = context.coordinator] text in
            coordinator?.onPasteBlock?(text) ?? false
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PastingTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onPasteBlock = onPasteBlock
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onPasteBlock: ((String) -> Bool)?

        init(text: Binding<String>, onPasteBlock: ((String) -> Bool)?) {
            self.text = text
            self.onPasteBlock = onPasteBlock
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  text.wrappedValue != textView.string
            else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class PastingTextView: NSTextView {
    var pasteBlock: ((String) -> Bool)?

    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string),
           pasteBlock?(text) == true {
            return
        }
        super.paste(sender)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
