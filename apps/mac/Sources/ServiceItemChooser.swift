import AppKit
import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

struct OpenLyricsImportResult: Sendable {
    var ids: [String]
    var failures: [String]
}

struct ServiceItemChooser: View {
    let model: AppModel
    let serviceID: String

    var render: RenderContext? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var tab: ServiceItemChooserLogic.Tab = .library
    @State private var query = ""
    @State private var filter: ServiceItemChooserLogic.KindFilter = .all

    @State private var queryHits: [LibraryIndex.Hit] = []

    @State private var idleOrder: [String] = []
    @State private var choosingFiles = false
    @State private var dropTargeted = false

    @State private var skippedNote: String?
    @State private var newName = ""
    @State private var newThemeId = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("Source", selection: $tab) {
                ForEach(ServiceItemChooserLogic.Tab.allCases, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            Group {
                switch tab {
                case .importFile: importPane
                case .new: newPane
                default: libraryPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(10)
        }
        .frame(width: 600, height: 480)
        .onAppear {
            searchFocused = true
            idleOrder = ServiceItemChooserLogic.results(query: "", hits: [], idle: idleEntries, filter: .all).map(\.entry.id)
        }
        .task(id: query) {
            queryHits = await model.search(query)
        }
        .fileImporter(
            isPresented: $choosingFiles, allowedContentTypes: ServiceItemChooserLogic.importTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importUsable(urls) }
        }
    }

    private var libraryPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    TextField("Search the library", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle.standard(CornerStandard.element))
                Picker("Show", selection: $filter) {
                    ForEach(ServiceItemChooserLogic.KindFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(10)
            Divider()
            let hits = results
            List(hits, id: \.entry.id) { hit in
                row(hit)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if hits.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "No Slides or Media", systemImage: "magnifyingglass",
                            description: Text("Import a file or make a new presentation from the tabs above.")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
    }

    private var results: [LibraryIndex.Hit] {
        let hits = ServiceItemChooserLogic.results(query: query, hits: queryHits, idle: idleEntries, filter: filter)
        return query.trimmingCharacters(in: .whitespaces).isEmpty
            ? ServiceItemChooserLogic.steady(hits, order: idleOrder)
            : hits
    }

    private var idleEntries: [LibraryIndex.Entry] {
        model.entries(of: .presentation) + model.entries(of: .media)
    }

    @ViewBuilder
    private func row(_ hit: LibraryIndex.Hit) -> some View {
        let accessory: String? = "plus.circle"
        if hit.entry.kind == .presentation {
            LibraryPickerDeckRow(
                appModel: model, render: render, entry: hit.entry,
                snippet: hit.snippet, accessory: accessory
            ) {
                pick(hit.entry)
            }
        } else {
            Button {
                pick(hit.entry)
            } label: {
                HStack(spacing: 8) {
                    if hit.entry.kind == .media {

                        Color.black
                            .overlay { PosterImage(model: model, mediaId: hit.entry.id) }
                            .frame(width: 46, height: 26)
                            .clipShape(RoundedRectangle.standard(CornerStandard.element))
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(width: 46)
                    }
                    Text(hit.entry.name)
                        .lineLimit(1)
                    Spacer()
                    if let used = hit.entry.lastUsedAt {
                        Text("Used \(used, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let accessory {
                        Image(systemName: accessory)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func pick(_ entry: LibraryIndex.Entry) {
        model.addServiceItem(serviceID, refID: entry.id)
    }

    private var importPane: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop a file here, or choose one")
                .font(.headline)
            Text("Images and video, PowerPoint (.pptx), Chorus (.chorus), OpenLyrics XML, lyrics or ChordPro text, chord chart PDFs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text("Each file becomes a service item.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let skippedNote {
                Label(skippedNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle.standard(CornerStandard.element)
                .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .padding(16)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            importUsable(urls)
        } isTargeted: { dropTargeted = $0 }
    }

    @discardableResult
    private func importUsable(_ urls: [URL]) -> Bool {
        if let refusal = ServiceItemChooserLogic.refusal(urls) {
            skippedNote = refusal
            return false
        } else {
            importNow(urls.filter { ServiceItemChooserLogic.route($0) != nil })
            return true
        }
    }

    private func importNow(_ urls: [URL]) {
        let serviceID = serviceID
        let model = model
        dismiss()
        Task { @MainActor in
            for id in await model.importForService(urls) {
                model.addServiceItem(serviceID, refID: id)
            }
        }
    }

    private var newPane: some View {
        Form {
            TextField("Name", text: $newName, prompt: Text("Untitled Presentation"))
            LabeledContent("Theme") {
                LyricsThemeChooser(appModel: model, render: render, themeId: newThemeId) { themeId, _ in
                    newThemeId = themeId
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func createNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "Untitled Presentation" : trimmed
        if let id = model.createPresentation(named: name, themeId: newThemeId) {
            model.addServiceItem(serviceID, refID: id)
            dismiss()
        }
    }

    private var footer: some View {
        HStack {
            if tab == .importFile {
                Button("Choose Files…") { choosingFiles = true }
            }
            Spacer()
            if tab == .library {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if tab == .new {
                Button("Create and Add") { createNew() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

extension AppModel {

    func importForService(_ urls: [URL]) async -> [String] {
        var landed: [String] = []
        for route in ServiceItemChooserLogic.ImportRoute.allCases {
            let files = urls.filter { ServiceItemChooserLogic.route($0) == route }
            if !files.isEmpty {
                landed += await importFiles(files, through: route)
            }
        }
        await client.settled()
        return landed
    }

    private func importFiles(_ files: [URL], through route: ServiceItemChooserLogic.ImportRoute) async -> [String] {
        switch route {
        case .slidesFile: await importPresentationFiles(files)
        case .powerPoint: await runPowerPointImport(files)
        case .lyrics: await importLyricsFiles(files)
        case .openLyrics: await importOpenLyricsFiles(files)
        case .media: await importFiles(files)
        }
    }

    func importLyricsFiles(_ urls: [URL]) async -> [String] {
        var ids: [String] = []
        for url in urls {
            let text = await Task.detached {
                (try? Data(contentsOf: url)).flatMap { ChordChartPDF.importText(from: $0, filename: url.lastPathComponent) }
            }.value
            if let text, let id = importLyrics(
                text: text,
                fallbackTitle: url.deletingPathExtension().lastPathComponent,
                themeId: slideBuilding.lyricsImportThemeId ?? "",
                themeSlideName: slideBuilding.lyricsDesign,
                origin: PresentationOrigin(
                    url.pathExtension.lowercased() == "pdf" ? .chartFile : .lyricsFile,
                    detail: url.lastPathComponent)
            ) {
                ids.append(id)
            }
        }
        return ids
    }

    func importOpenLyricsFiles(_ urls: [URL], linesPerSlide: Int = 2, includeTransliteration: Bool = true) async -> [String] {
        var ids: [String] = []
        var failures: [String] = []
        for url in urls {
            let result = await Task.detached(priority: .userInitiated) {
                () -> ([OpenLyricsImporter.Song]?, String?) in
                do {
                    return (try OpenLyricsImporter.parseSongs(Data(contentsOf: url)), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            guard let songs = result.0 else {
                failures.append("\(url.lastPathComponent): \(result.1 ?? "Could not read OpenLyrics file")")
                continue
            }
            let importResult = await importOpenLyricsSongs(
                songs, sourceName: url.lastPathComponent,
                linesPerSlide: linesPerSlide, includeTransliteration: includeTransliteration
            )
            ids += importResult.ids
            failures += importResult.failures
        }
        if !ids.isEmpty || !failures.isEmpty {
            let imported = ids.isEmpty ? nil : "Imported \(ids.count) OpenLyrics song\(ids.count == 1 ? "" : "s")"
            let details = [imported].compactMap { $0 } + failures
            noteImportSummary(details.joined(separator: "\n"))
        }
        return ids
    }

    @discardableResult
    func importOpenLyricsSongs(
        _ songs: [OpenLyricsImporter.Song],
        sourceName: String,
        linesPerSlide: Int = 2,
        includeTransliteration: Bool = true,
        onProgress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async -> OpenLyricsImportResult {
        let chunkSize = LibraryClient.bulkChunkSize
        var result = OpenLyricsImportResult(ids: [], failures: [])

        for start in stride(from: 0, to: songs.count, by: chunkSize) {
            let end = min(start + chunkSize, songs.count)
            let chunk = Array(songs[start..<end])
            let lyricSongs = chunk.enumerated().map { offset, source in
                var song = SongLyrics.openLyrics(
                    source, includeTransliteration: includeTransliteration
                )
                if source.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    song.name = "\(sourceName) - Song \(start + offset + 1)"
                }
                return song
            }

            do {
                _ = try await createInDrive(lyricSongs).value
                result.ids.append(contentsOf: lyricSongs.map(\.id))
            } catch {
                let writeError = error.localizedDescription
                do {
                    let snapshot = try await client.settledSnapshot()
                    let persistedIDs = Set(snapshot.entries(of: .song).map(\.id))
                    for song in lyricSongs {
                        if persistedIDs.contains(song.id) {
                            result.ids.append(song.id)
                        } else {
                            result.failures.append("\(song.name): \(writeError)")
                        }
                    }
                } catch {
                    result.failures.append(
                        "\(sourceName) songs \(start + 1)-\(end): \(writeError); "
                            + "could not verify which records were saved: \(error.localizedDescription)")
                }
            }
            onProgress?(end, songs.count)
            await Task.yield()
        }
        return result
    }
}
