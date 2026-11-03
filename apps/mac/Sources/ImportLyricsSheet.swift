import PresenterCore
import SlideScene
import SwiftUI
import UniformTypeIdentifiers

struct ImportLyricsSheet: View {
    let model: AppModel
    let render: RenderContext?
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var secondaryLyrics = ""
    @State private var transliteration = ""
    @State private var usesSecondaryLanguage = false
    @State private var usesTransliteration = false
    @State private var transliterationSource = "primary"

    @State private var loadedFrom: PresentationOrigin?
    @State private var loadedCCLI: CCLIInfo?
    @State private var loadedMusicKey: String?
    @State private var loadError: String?
    @State private var title = ""
    @State private var linesPerSlide = 2

    @State private var lyricLines: Set<String> = []
    @State private var showChords = false

    @State private var showingChordLines = false

    @State private var preview: Preview?

    private var themeId: String { model.slideBuilding.lyricsImportThemeId ?? "" }

    private var design: String { model.slideBuilding.lyricsDesign }

    struct Input: Equatable, Sendable {
        var text: String
        var linesPerSlide: Int
        var lyricLines: Set<String>
        var themeId: String
        var design: String
        var secondaryLyrics: String
        var transliteration: String
    }

    struct Preview: Sendable {

        struct Group: Sendable {
            var name: String
            var slides: [Slide]
        }

        var format: LyricTextFormat?
        var presentation: Presentation
        var groups: [Group]

        var arrangement: String?
        var chordLines: [String]
        var hasChords: Bool
    }

    private var input: Input {
        Input(
            text: text, linesPerSlide: linesPerSlide, lyricLines: lyricLines,
            themeId: themeId, design: design,
            secondaryLyrics: usesSecondaryLanguage ? secondaryLyrics : "",
            transliteration: usesTransliteration ? transliteration : "")
    }

    private var lineCountMismatch: Bool {
        let primaryCount = LyricTextImporter.lyricLineCount(text)
        guard primaryCount > 0 else { return false }
        if usesSecondaryLanguage, !secondaryLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           LyricTextImporter.lyricLineCount(secondaryLyrics) != primaryCount {
            return true
        }
        return usesTransliteration && !transliteration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && LyricTextImporter.lyricLineCount(transliteration) != primaryCount
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Lyrics")
                    .font(.headline)
                Spacer()
                if let format = preview?.format {
                    Text(LocalizedStringKey(Self.formatCaption(format)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            HSplitView {
                editor
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                previewPane
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
                .padding(12)
        }
        .frame(minWidth: 940, minHeight: 600)
        .alert(
            "Couldn’t load lyrics",
            isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .task(id: input) {
            let input = input
            let built = await Task.detached(priority: .userInitiated) { Self.build(input) }.value
            if !Task.isCancelled { preview = built }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)

                .font(preview?.chordLines.isEmpty == false ? .body.monospaced() : .body)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste lyrics or a chord chart — SongSelect, ChordPro, and chords above the words are detected automatically. Blank lines split slides; Verse 1, Chorus… start sections.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if let lines = preview?.chordLines, !lines.isEmpty {
                chordLineList(lines)
            }
            Toggle("Add a second language", isOn: $usesSecondaryLanguage)
                .toggleStyle(.checkbox)
            if usesSecondaryLanguage {
                TextEditor(text: $secondaryLyrics)
                    .font(.body)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if secondaryLyrics.isEmpty {
                            Text("Paste the second language in matching line order.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
            Toggle("Add transliteration", isOn: $usesTransliteration)
                .toggleStyle(.checkbox)
            if usesTransliteration {
                HStack {
                    Picker("From", selection: $transliterationSource) {
                        Text("Primary lyrics").tag("primary")
                        Text("Second language").tag("secondary")
                    }
                    .labelsHidden()
                    .disabled(!usesSecondaryLanguage)
                    Button("Generate") {
                        let source = transliterationSource == "secondary" ? secondaryLyrics : text
                        let normalized = LyricTextImporter.normalize(source).body
                        transliteration = LyricTextImporter.transliterateToLatin(normalized)
                    }
                    .disabled((transliterationSource == "secondary" ? secondaryLyrics : text).isEmpty)
                }
                TextEditor(text: $transliteration)
                    .font(.body)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if transliteration.isEmpty {
                            Text("Generate it, then edit as needed—or enter it yourself.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
            if lineCountMismatch {
                Label("Language lines must match the primary lyrics.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    private func chordLineList(_ lines: [String]) -> some View {
        DisclosureGroup(isExpanded: $showingChordLines) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines, id: \.self) { line in
                        HStack {
                            Text(line)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Picker("", selection: lyricBinding(line)) {
                                Text("Chords").tag(false)
                                Text("Lyrics").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .help("Read this line as chords over the next line, or as words on the slide")
                        }
                    }
                }
            }
            .frame(maxHeight: 140)
        } label: {
            Text("Lines read as chords (\(lines.count)) — flip any that are really words")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func lyricBinding(_ line: String) -> Binding<Bool> {
        Binding(
            get: { lyricLines.contains(line) },
            set: { isLyric in
                if isLyric { lyricLines.insert(line) } else { lyricLines.remove(line) }
            }
        )
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $showChords) {
                    Text("Audience").tag(false)
                    Text("With Chords").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(preview?.hasChords != true)
                .help("Audience shows the slides as the audience screens will; With Chords shows the chords above the words, the confidence-monitor read")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if let preview, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ImportLyricsPreview(
                    model: model, render: render, preview: preview,
                    showChords: showChords && preview.hasChords)
            } else {
                ContentUnavailableView(
                    "Paste Lyrics", systemImage: "text.alignleft",
                    description: Text("The slides appear here as you type.")
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var summary: String {
        if let presentation = preview?.presentation, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sections = presentation.sections?.count ?? 0
            return "\(sections) section\(sections == 1 ? "" : "s") · \(presentation.slides.count) slide\(presentation.slides.count == 1 ? "" : "s")"
        } else {
            return "Preview"
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Load File…", action: loadFile)
                .help("Lyrics, ChordPro, OpenLyrics XML, or a chord chart PDF")
            TextField("Title (optional — SongSelect and ChordPro carry their own)", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
            Stepper("Lines per slide: \(linesPerSlide)", value: $linesPerSlide, in: 1...8)
                .fixedSize()
            LyricsThemeChooser.lyrics(model, render: render)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Import", action: importNow)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lineCountMismatch)
        }
    }

    static func formatCaption(_ format: LyricTextFormat) -> String {
        switch format {
        case .songSelect: return "Detected: SongSelect lyrics — CCLI number will be stamped"
        case .chordPro: return "Detected: ChordPro — chords stripped for slides, kept for charts"
        case .chordChart: return "Detected: chord chart — chords above the words become the song's chords"
        case .plainText: return "Plain text — blank lines split slides, labels make sections"
        }
    }

    nonisolated static func build(_ input: Input) -> Preview {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let presentation = LyricTextImporter.makePresentation(
            input.text, id: "lyrics-import-preview", themeId: input.themeId, themeSlideName: input.design,
            linesPerSlide: input.linesPerSlide, lyricLines: input.lyricLines,
            secondaryLyrics: input.secondaryLyrics.isEmpty ? nil : input.secondaryLyrics,
            transliteration: input.transliteration.isEmpty ? nil : input.transliteration)
        let names = Dictionary(
            (presentation.sections ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var groups: [(sectionID: String?, slides: [Slide])] = []
        for slide in presentation.slides {
            if let last = groups.last, last.sectionID == slide.sectionId {
                groups[groups.count - 1].slides.append(slide)
            } else {
                groups.append((slide.sectionId, [slide]))
            }
        }
        return Preview(
            format: trimmed.isEmpty ? nil : LyricTextImporter.detectFormat(input.text, lyricLines: input.lyricLines),
            presentation: presentation,
            groups: groups.map { Preview.Group(name: $0.sectionID.flatMap { names[$0] } ?? "Slides", slides: $0.slides) },
            arrangement: presentation.arrangements?.first.map { $0.sectionIds.compactMap { names[$0] }.joined(separator: " → ") },
            chordLines: LyricTextImporter.chordChartLines(input.text),
            hasChords: ChordMath.hasChords(in: presentation)
        )
    }

    static func namesItsTitle(_ text: String) -> Bool {
        LyricTextImporter.normalize(text).title != nil
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .pdf]
            + ["cho", "chopro", "crd", "chordpro", "xml"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            Task { @MainActor in
                let result = await Task.detached {
                    () -> (
                        songs: [OpenLyricsImporter.Song]?, text: String?, title: String?,
                        ccli: CCLIInfo?, musicKey: String?, error: String?
                    ) in
                    if url.pathExtension.lowercased() == "xml" {
                        do {
                            let songs = try OpenLyricsImporter.parseSongs(data)
                            guard let song = songs.first else {
                                return (nil, nil, nil, nil, nil, "No songs were found.")
                            }
                            return (songs, song.lyricsText, song.title, song.ccli, song.musicKey, nil)
                        } catch {
                            return (nil, nil, nil, nil, nil, error.localizedDescription)
                        }
                    }
                    return (
                        nil, ChordChartPDF.importText(from: data, filename: url.lastPathComponent),
                        nil, nil, nil, nil
                    )
                }.value
                if let songs = result.songs {
                    let imported = await model.importOpenLyricsSongs(songs, sourceName: url.lastPathComponent)
                    var summary = "Imported \(imported.ids.count) OpenLyrics song\(imported.ids.count == 1 ? "" : "s") from \(url.lastPathComponent)"
                    if !imported.failures.isEmpty {
                        summary += " — \(imported.failures.count) failed: \(imported.failures.prefix(3).joined(separator: "; "))"
                    }
                    model.noteImportSummary(summary)
                    await model.client.settled()
                    dismiss()
                    if let id = imported.ids.first { onImported(id) }
                    return
                }
                if let contents = result.text {
                    text = contents
                    loadedCCLI = result.ccli
                    loadedMusicKey = result.musicKey
                    if title.isEmpty, let importedTitle = result.title { title = importedTitle }
                    loadedFrom = PresentationOrigin(
                        url.pathExtension.lowercased() == "pdf" ? .chartFile : .lyricsFile,
                        detail: url.lastPathComponent)
                    if title.isEmpty, !Self.namesItsTitle(contents) {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                } else {
                    loadError = result.error ?? "Could not extract lyrics from \(url.lastPathComponent)."
                }
            }
        }
    }

    private func importNow() {
        let fallback = title.trimmingCharacters(in: .whitespaces)
        let id = model.importLyrics(
            text: text,
            fallbackTitle: fallback.isEmpty ? nil : fallback,
            linesPerSlide: linesPerSlide,
            themeId: themeId,
            themeSlideName: design,
            lyricLines: lyricLines,
            secondaryLyrics: usesSecondaryLanguage ? secondaryLyrics : nil,
            transliteration: usesTransliteration ? transliteration : nil,
            ccli: loadedCCLI,
            musicKey: loadedMusicKey,
            origin: loadedFrom ?? PresentationOrigin(.pastedLyrics)
        )
        dismiss()
        if let id { onImported(id) }
    }
}

private struct ImportLyricsPreview: View {
    let model: AppModel
    let render: RenderContext?
    let preview: ImportLyricsSheet.Preview
    let showChords: Bool

    var body: some View {
        let themeId = preview.presentation.themeId
        let theme = themeId.isEmpty ? nil : model.theme(themeId)
        let themeStamp = model.entry(themeId)?.updatedAt.timeIntervalSince1970 ?? 0
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(preview.groups.enumerated()), id: \.offset) { _, group in
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Array(group.slides.enumerated()), id: \.offset) { _, slide in
                            ImportSlideThumbnail(
                                model: model, render: render, slide: slide, theme: theme,
                                showChords: showChords,
                                cacheKey: Self.cacheKey(slide, themeId: themeId, themeStamp: themeStamp, showChords: showChords))
                        }
                    }
                }
                if let arrangement = preview.arrangement {
                    Text("Arrangement: " + arrangement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    static func cacheKey(_ slide: Slide, themeId: String, themeStamp: Double, showChords: Bool) -> String {
        let content = slide.objects.map { object in
            object.text + "|" + (object.chords ?? []).map { "\($0.line).\($0.column).\($0.symbol)" }.joined(separator: ",")
        }.joined(separator: "¶")
        return "lyrics-import|\(themeId)|\(themeStamp)|\(slide.themeSlideName ?? "")|\(showChords)|\(content)"
    }
}

private struct ImportSlideThumbnail: View {
    let model: AppModel
    let render: RenderContext?
    let slide: Slide
    let theme: Theme?
    let showChords: Bool
    let cacheKey: String

    var body: some View {
        var shown = slide
        if showChords { shown.objects = ChordEditing.revealed(slide.objects) }
        let canvas = SlideSceneBuilder.canvasSize
        return ZStack {
            TransparencyGrid()
            if let image = ThumbnailStore.shared.slideContent(
                slide: shown, theme: theme, render: render, model: model,
                canvas: canvas, cacheKey: cacheKey
            ) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            if slide.objects.isEmpty {
                Text("Blank")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}
