import Foundation
import Observation
import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

fileprivate struct BibleVersionIndex: Sendable {
    struct SearchEntry: Sendable {
        let verse: BibleXMLImporter.Verse
        let normalizedText: String
    }

    let versionID: String
    let versionName: String
    let books: [String]
    let chaptersByBook: [String: [Int]]
    let versesByChapter: [String: [BibleXMLImporter.Verse]]
    let versesByID: [String: BibleXMLImporter.Verse]
    let searchEntries: [SearchEntry]
    let searchTrigrams: [String: [Int]]

    init(_ version: BibleXMLImporter.Version) {
        versionID = version.id
        versionName = version.name
        let versesByBook = Dictionary(grouping: version.verses, by: \.book)
        books = version.books
        chaptersByBook = versesByBook.mapValues { verses in
            Array(Set(verses.map(\.chapter))).sorted()
        }
        versesByChapter = Dictionary(grouping: version.verses) {
            "\($0.book)|\($0.chapter)"
        }.mapValues { verses in
            verses.sorted { $0.number < $1.number }
        }
        versesByID = Dictionary(
            version.verses.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entries = version.verses.map { verse in
            SearchEntry(
                verse: verse,
                normalizedText: Self.normalize(verse.text)
            )
        }
        searchEntries = entries
        var trigrams: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            let characters = Array(entry.normalizedText)
            guard characters.count >= 3 else { continue }
            var seen: Set<String> = []
            for start in 0...(characters.count - 3) {
                let trigram = String(characters[start..<(start + 3)])
                if seen.insert(trigram).inserted {
                    trigrams[trigram, default: []].append(index)
                }
            }
        }
        searchTrigrams = trigrams
    }

    fileprivate static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalized = folded
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { result, character in
                if character == " " {
                    if result.last?.isWhitespace != true { result.append(character) }
                } else {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0 == "oh" ? "o" : String($0) }
            .joined(separator: " ")
    }
}

@MainActor
@Observable
final class BibleLibraryStore {
    private(set) var versions: [BibleXMLImporter.Version] = []
    fileprivate var indexes: [String: BibleVersionIndex] = [:]
    private(set) var errors: [String] = []
    private(set) var loading = true
    private(set) var importing = false
    private(set) var importProgress = 0
    private(set) var importTotal = 0

    private(set) var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private let folderURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folderURL = support.appendingPathComponent("Chorus/Bible Versions", isDirectory: true)
    }

    func load() async {
        guard !hasLoaded else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await loadOnce() }
        loadTask = task
        await task.value
    }

    private func loadOnce() async {
        loading = true
        defer {
            loading = false
            loadTask = nil
        }
        do {
            let result = try await Task.detached(priority: .userInitiated) { [folderURL] in
                try FileManager.default.createDirectory(
                    at: folderURL, withIntermediateDirectories: true
                )
                let files = try FileManager.default.contentsOfDirectory(
                    at: folderURL, includingPropertiesForKeys: nil
                ).filter { $0.pathExtension == "json" }
                var versions: [BibleXMLImporter.Version] = []
                var errors: [String] = []
                for url in files {
                    do {
                        versions.append(try JSONDecoder().decode(
                            BibleXMLImporter.Version.self, from: Data(contentsOf: url)
                        ))
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                let indexes = Dictionary(
                    versions.map { ($0.id, BibleVersionIndex($0)) },
                    uniquingKeysWith: { first, _ in first }
                )
                return (versions, errors, indexes)
            }.value
            versions = result.0.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            indexes = result.2
            errors = result.1
            hasLoaded = true
        } catch {
            errors = ["Could not load saved Bible versions: \(error.localizedDescription)"]
        }
    }

    func reportError(_ error: String) {
        errors = [error]
    }

    func clearErrors() {
        errors = []
    }

    func importFiles(_ urls: [URL], versionName: String) async {
        importing = true
        importProgress = 0
        importTotal = urls.count
        errors = []
        defer { importing = false }

        for url in urls {
            do {
                let sourceName = url.lastPathComponent
                let baseName = url.deletingPathExtension().lastPathComponent
                let label = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = urls.count == 1 && !label.isEmpty ? label : baseName
                let (version, index) = try await Task.detached(priority: .userInitiated) {
                    let hasScopedAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasScopedAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let version = try BibleXMLImporter.parse(
                        Data(contentsOf: url), versionName: name, sourceName: sourceName
                    )
                    return (version, BibleVersionIndex(version))
                }.value
                try await Task.detached(priority: .utility) { [folderURL] in
                    try FileManager.default.createDirectory(
                        at: folderURL, withIntermediateDirectories: true
                    )
                    let payload = try JSONEncoder().encode(version)
                    let destination = folderURL.appendingPathComponent("\(version.id).json")
                    try payload.write(to: destination, options: .atomic)
                }.value
                versions.append(version)
                indexes[version.id] = index
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            importProgress += 1
        }
        versions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct BibleLibraryView: View {
    let model: AppModel
    let store: BibleLibraryStore
    let controls: ServiceControls?
    let presets: OutputPresetsController?
    let onCreated: (String) -> Void

    @State private var showingFilePicker = false
    @State private var versionName = ""
    @State private var englishVersionID = ""
    @State private var tamilVersionID = ""
    @State private var selectedBook = ""
    @State private var selectedChapter = 1
    @State private var showingVerses = false
    @State private var pendingChapterSelection: Int?
    @State private var passageQuery = ""
    @State private var textSearch = ""
    @State private var searchResults: [BibleXMLImporter.SearchHit] = []
    @State private var isSearching = false
    @State private var lowerThirdThemeID = ""
    @State private var lowerThirdWorking = false
    @State private var actionError: String?
    private var englishVersion: BibleXMLImporter.Version? {
        store.versions.first { $0.id == englishVersionID } ?? store.versions.first
    }

    private var tamilVersion: BibleXMLImporter.Version? {
        store.versions.first { $0.id == tamilVersionID } ?? store.versions.first
    }

    private var englishIndex: BibleVersionIndex? {
        store.indexes[englishVersion?.id ?? ""]
    }

    private var tamilIndex: BibleVersionIndex? {
        store.indexes[tamilVersion?.id ?? ""]
    }

    private var books: [String] { englishIndex?.books ?? [] }

    private var chapters: [Int] {
        englishIndex?.chaptersByBook[selectedBook] ?? []
    }

    private var verses: [BibleXMLImporter.Verse] {
        englishIndex?.versesByChapter[chapterID(selectedBook, selectedChapter)] ?? []
    }

    private var searchKey: String {
        "\(textSearch.trimmingCharacters(in: .whitespacesAndNewlines))|\(englishVersionID)|\(tamilVersionID)"
    }

    private var lowerThirdThemeName: String {
        presets?.themes.first(where: { $0.id == lowerThirdThemeID })?.name ?? "Choose a theme"
    }

    private var tamilVersesByID: [String: BibleXMLImporter.Verse] {
        tamilIndex?.versesByID ?? [:]
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.versions.isEmpty {
                if store.loading {
                    ProgressView("Loading Bible versions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyLibrary
                }
            } else {
                versionControls
                Divider()
                searchField
                Divider()
                bookIndex
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.basePlane)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: ["xml"].compactMap { UTType(filenameExtension: $0) },
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await store.importFiles(urls, versionName: versionName) }
            case .failure(let error):
                store.reportError(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingLowerThirdControls) {
            lowerThirdControls
                .frame(minWidth: 520, minHeight: 230)
        }
        .onChange(of: store.versions.count, initial: true) { _, _ in
            chooseInitialVersions()
        }
        .onChange(of: englishVersionID) { _, _ in
            selectedBook = ""
            showingVerses = false
            selectedChapter = 1
            pendingChapterSelection = nil
        }
        .onChange(of: selectedBook) { _, _ in
            let nextChapter = pendingChapterSelection ?? chapters.first ?? 1
            selectedChapter = nextChapter
            pendingChapterSelection = nil
        }
        .onChange(of: selectedChapter) { _, _ in
            pendingChapterSelection = nil
        }
        .task(id: searchKey) {
            let query = textSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isSearching = true
            var selectedIndexes = [englishIndex, tamilIndex].compactMap { $0 }
            var seenVersionIDs: Set<String> = []
            selectedIndexes = selectedIndexes.filter { seenVersionIDs.insert($0.versionID).inserted }
            let results = await Task.detached(priority: .userInitiated) {
                Self.search(query: query, in: selectedIndexes)
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }

        .onAppear {
            lowerThirdThemeID = NDIScreenOutputs.shared.lowerThirdThemeID ?? ""
        }
        .alert("Bible Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "The requested action could not be completed.")
        }
    }

    nonisolated private static func search(
        query: String, in indexes: [BibleVersionIndex], limit: Int = 200
    ) -> [BibleXMLImporter.SearchHit] {
        if let reference = BibleXMLImporter.reference(from: query) {
            return indexes.flatMap { index in
                (index.versesByChapter["\(reference.book)|\(reference.chapter)"] ?? []).lazy
                    .filter { verse in
                        reference.verses.map { $0.contains(verse.number) } ?? true
                    }
                    .prefix(limit)
                    .map {
                        BibleXMLImporter.SearchHit(
                            versionID: index.versionID,
                            versionName: index.versionName,
                            verse: $0
                        )
                    }
            }.prefix(limit).map { $0 }
        }

        let normalizedQuery = BibleVersionIndex.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let queryTokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return indexes.flatMap { index in
            let candidateIndexes: [Int]
            if queryTokens.count > 1 {
                candidateIndexes = Array(index.searchEntries.indices)
            } else if normalizedQuery.count < 3 {
                candidateIndexes = Array(index.searchEntries.indices)
            } else {
                let queryCharacters = Array(normalizedQuery)
                let queryTrigrams = (0...(queryCharacters.count - 3)).map {
                    String(queryCharacters[$0..<($0 + 3)])
                }
                let postings = queryTrigrams.compactMap({
                    index.searchTrigrams[$0]
                })
                candidateIndexes = postings.min(by: { $0.count < $1.count }) ?? []
            }
            return candidateIndexes.lazy
                .compactMap { index.searchEntries.indices.contains($0) ? index.searchEntries[$0] : nil }
                .filter { entry in
                    entry.normalizedText.contains(normalizedQuery)
                        || queryTokens.allSatisfy { token in entry.normalizedText.contains(token) }
                }
                .prefix(limit)
                .map {
                    BibleXMLImporter.SearchHit(
                        versionID: index.versionID,
                        versionName: index.versionName,
                        verse: $0.verse
                    )
                }
        }.prefix(limit).map { $0 }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 8) {
            ContentUnavailableView(
                "No Bible Versions",
                systemImage: "book.closed",
                description: Text("Import OSIS or Zefania Bible XML to build the book index.")
            )
            Button {
                showingFilePicker = true
            } label: {
                Label("Import Bible XML…", systemImage: "square.and.arrow.down")
            }
            .disabled(store.importing || store.loading)
            if store.importing {
                ProgressView(value: Double(store.importProgress), total: Double(max(store.importTotal, 1)))
                Text("Importing Bible \(store.importProgress) of \(store.importTotal)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            errorList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionControls: some View {
        HStack(spacing: 4) {
            Picker("Tamil", selection: $tamilVersionID) {
                ForEach(store.versions) { version in
                    Text(shortVersionName(version)).tag(version.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Picker("English", selection: $englishVersionID) {
                ForEach(store.versions) { version in
                    Text(shortVersionName(version)).tag(version.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func shortVersionName(_ version: BibleXMLImporter.Version) -> String {
        let name = version.name
        if name.localizedCaseInsensitiveContains("tamil") { return "TAM" }
        let parts = name.split { !$0.isLetter && !$0.isNumber }
        if let abbreviation = parts.last, abbreviation.count <= 6 {
            return abbreviation.uppercased()
        }
        return name
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search verses…", text: $textSearch)
                .textFieldStyle(.plain)
                .onSubmit {
                    passageQuery = textSearch
                    jumpToPassage(reportsError: false)
                }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !textSearch.isEmpty {
                Button {
                    textSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            Menu {
                Button("Import Bible XML…", systemImage: "square.and.arrow.down") {
                    showingFilePicker = true
                }
                .disabled(store.importing || store.loading)
                Divider()
                if controls != nil, presets != nil {
                    Divider()
                    Button("Lower Third NDI Settings…") {
                        showingLowerThirdControls.toggle()
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("Bible options")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle.standard(CornerStandard.element))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    @State private var showingLowerThirdControls = false

    private var bookIndex: some View {
        Group {
            if !textSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                verseList
            } else if selectedBook.isEmpty {
                bookList
            } else if showingVerses {
                chapterVerses
            } else {
                chapterGrid
            }
        }
    }

    private var bookList: some View {
        List(books, id: \.self) { book in
            Button {
                selectedBook = book
                selectedChapter = chaptersForBook(book).first ?? 1
                showingVerses = false
            } label: {
                HStack {
                    Text(book)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 12))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var chapterGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    selectedBook = ""
                } label: {
                    Label(selectedBook, systemImage: "chevron.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("CHAPTERS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.cyan)
                Text("\(chapters.count) total")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            Divider()
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                    spacing: 5
                ) {
                    ForEach(chapters, id: \.self) { chapter in
                        Button {
                            selectChapter(selectedBook, chapter)
                            showingVerses = true
                        } label: {
                            Text("\(chapter)")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    private var chapterVerses: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    showingVerses = false
                } label: {
                    Label("\(selectedBook) \(selectedChapter)", systemImage: "chevron.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    presentChapter()
                } label: {
                    Label("Present chapter", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(verses.isEmpty || controls == nil)
                Text("VERSES")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Divider()
            verseList
        }
    }

    private var verseList: some View {
        let tamilByID = tamilVersesByID
        return Group {
            if textSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                List(verses) { verse in
                    verseRow(verse, tamil: tamilByID[verse.id])
                }
                .overlay {
                    if verses.isEmpty {
                        ContentUnavailableView("No Verses", systemImage: "book")
                    }
                }
            } else {
                List(searchResults) { hit in
                    Button {
                        selectSearchResult(hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(hit.verse.book) \(hit.verse.chapter):\(hit.verse.number)")
                                    .font(.caption.weight(.semibold))
                                Text(hit.versionName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(hit.verse.text)
                            if let tamil = tamilByID[hit.verse.id] {
                                Text(tamil.text)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .overlay {
                    if !isSearching, searchResults.isEmpty {
                        ContentUnavailableView("No Matching Verses", systemImage: "text.magnifyingglass")
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func verseRow(
        _ verse: BibleXMLImporter.Verse,
        tamil: BibleXMLImporter.Verse?
    ) -> some View {
        let isLive = controls?.livePresentationID == biblePresentationID(for: verse)
        return Button {
            showVerse(verse)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(verse.number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isLive ? Color.accentColor : .secondary)
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verse.text)
                    if let tamil {
                        Text(tamil.text)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                Spacer(minLength: 0)
                if isLive {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isLive ? Color.accentColor.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
        .disabled(controls == nil)
    }

    private var lowerThirdControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Dedicated Lower Third NDI", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Theme", selection: $lowerThirdThemeID) {
                    Text("Choose a theme").tag("")
                    ForEach(presets?.themes ?? [], id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .frame(width: 250)
            }
            HStack(alignment: .center, spacing: 12) {
                lowerThirdPreview
                    .frame(width: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.separator.opacity(0.6))
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview · \(lowerThirdThemeName)")
                        .font(.caption.weight(.medium))
                    Text("Only the Slide layer is sent on this separate NDI feed, with a transparent background. The selected theme applies automatically while the main outputs keep their current routing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(lowerThirdWorking ? "Starting…" : "Start / Update Feed") {
                            activateLowerThirdOutput()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(lowerThirdThemeID.isEmpty || lowerThirdWorking)
                        if NDIScreenOutputs.shared.lowerThirdScreenID != nil {
                            Button("Stop Feed", role: .destructive) {
                                stopLowerThirdOutput()
                            }
                            .disabled(lowerThirdWorking)
                        }
                        lowerThirdOutputStatus
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task(id: lowerThirdThemeID) {
            guard !lowerThirdThemeID.isEmpty else { return }
            await model.themesFilled([lowerThirdThemeID])
        }
    }

    @ViewBuilder
    private var lowerThirdPreview: some View {
        if !lowerThirdThemeID.isEmpty,
           let theme = model.theme(lowerThirdThemeID),
           let verse = verses.first {
            let slide = makeSlide(
                for: verse,
                sectionID: "lower-third-preview",
                tamil: tamilVersesByID[verse.id]
            )
            let presentation = Presentation(
                id: "\(lowerThirdThemeID)|bible-lower-third-preview",
                name: "\(verse.book) \(verse.chapter):\(verse.number)",
                presentationKind: .deck,
                themeId: lowerThirdThemeID,
                slides: [slide]
            )
            SlideThumbnailView(
                model: model,
                render: controls?.render,
                slide: slide,
                presentation: presentation,
                theme: theme,
                arrangementId: nil,
                hideScopedBackgrounds: false,
                contentStamp: "bible-lower-third|\(lowerThirdThemeID)|\(verse.id)"
            )
        } else {
            ContentUnavailableView("Select a Theme", systemImage: "textformat")
        }
    }

    @ViewBuilder
    private var lowerThirdOutputStatus: some View {
        if let screenID = NDIScreenOutputs.shared.lowerThirdScreenID,
           let status = NDIScreenOutputs.shared.status(for: screenID) {
            switch status {
            case .sending(let name):
                Label("Sending \(name)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .starting:
                Label("Connecting…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .interrupted(_):
                Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            case .idle:
                EmptyView()
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.importing {
                ProgressView(value: Double(store.importProgress), total: Double(max(store.importTotal, 1)))
                Text("Importing Bible \(store.importProgress) of \(store.importTotal)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            errorList
        }
        .padding(8)
    }

    private var errorList: some View {
        ForEach(store.errors, id: \.self) { error in
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func chooseInitialVersions() {
        guard !store.versions.isEmpty else { return }
        if !store.versions.contains(where: { $0.id == englishVersionID }) {
            englishVersionID = (store.versions.first {
                !$0.name.localizedCaseInsensitiveContains("tamil")
            } ?? store.versions[0]).id
        }
        if !store.versions.contains(where: { $0.id == tamilVersionID }) {
            tamilVersionID = (store.versions.first {
                $0.name.localizedCaseInsensitiveContains("tamil")
            } ?? store.versions[min(1, store.versions.count - 1)]).id
        }
        if !selectedBook.isEmpty, !chapters.contains(selectedChapter) {
            selectedChapter = chapters.first ?? 1
        }
    }

    private func jumpToPassage(reportsError: Bool = true) {
        let pattern = #"^\s*(.+?)\s+(\d+)(?::(\d+)(?:\s*[-–]\s*(\d+))?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: passageQuery, range: NSRange(passageQuery.startIndex..., in: passageQuery)
              ),
              let bookRange = Range(match.range(at: 1), in: passageQuery),
              let chapterRange = Range(match.range(at: 2), in: passageQuery),
              let chapter = Int(passageQuery[chapterRange]) else {
            if reportsError {
                store.reportError("Enter a reference such as John 3 or John 3:16.")
            }
            return
        }
        let bookName = BibleXMLImporter.canonicalBookName(String(passageQuery[bookRange]))
        guard books.contains(bookName), chaptersForBook(bookName).contains(chapter) else {
            if reportsError {
                store.reportError("That passage is not available in the selected English version.")
            }
            return
        }
        var verseNumber: Int?
        if match.range(at: 3).location != NSNotFound,
           let verseRange = Range(match.range(at: 3), in: passageQuery) {
            verseNumber = Int(passageQuery[verseRange])
        }
        selectPassage(bookName, chapter, verse: verseNumber)
        textSearch = ""
        store.clearErrors()
    }

    private func selectPassage(
        _ book: String, _ chapter: Int, verse: Int? = nil
    ) {
        pendingChapterSelection = chapter
        showingVerses = true
        if selectedBook == book {
            if selectedChapter == chapter {
                pendingChapterSelection = nil
            } else {
                selectedChapter = chapter
            }
        } else {
            selectedBook = book
        }
        if let verse,
           let match = englishIndex?.versesByChapter[chapterID(book, chapter)]?
               .first(where: { $0.number == verse }) {
            showVerse(match)
        }
    }

    private func selectSearchResult(_ hit: BibleXMLImporter.SearchHit) {
        let hasReference = englishIndex?.chaptersByBook[hit.verse.book]?.contains(hit.verse.chapter) ?? false
        if !hasReference {
            englishVersionID = hit.versionID
        }
        pendingChapterSelection = hit.verse.chapter
        selectedBook = hit.verse.book
        selectedChapter = hit.verse.chapter
        showingVerses = true
        showVerse(englishIndex?.versesByID[hit.verse.id] ?? hit.verse)
        passageQuery = "\(hit.verse.book) \(hit.verse.chapter):\(hit.verse.number)"
        textSearch = ""
        store.clearErrors()
    }

    private func chaptersForBook(_ book: String) -> [Int] {
        englishIndex?.chaptersByBook[book] ?? []
    }

    private func chapterID(_ book: String, _ chapter: Int) -> String {
        "\(book)|\(chapter)"
    }

    private func selectChapter(_ book: String, _ chapter: Int) {
        selectPassage(book, chapter)
    }

    private func showVerse(_ verse: BibleXMLImporter.Verse) {
        guard let controls else { return }
        let slide = makeSlide(
            for: verse, sectionID: "bible-\(verse.book)-\(verse.chapter)",
            tamil: tamilVersesByID[verse.id])
        let presentation = Presentation(
            id: biblePresentationID(for: verse),
            name: "\(verse.book) \(verse.chapter):\(verse.number)",
            presentationKind: .deck,
            themeId: "",
            slides: [slide],
            origin: PresentationOrigin(.madeHere, detail: "Bible XML live verse")
        )
        controls.toggleBibleVerse(slide: slide, in: presentation)
    }

    private func presentChapter() {
        guard let controls, !verses.isEmpty else { return }
        let slides = verses.map {
            makeSlide(
                for: $0,
                sectionID: "bible-\($0.book)-\($0.chapter)",
                tamil: tamilVersesByID[$0.id]
            )
        }
        let presentation = Presentation(
            id: "bible-passage:\(englishVersionID):\(selectedBook):\(selectedChapter)",
            name: "\(selectedBook) \(selectedChapter)",
            presentationKind: .deck,
            themeId: "",
            slides: slides,
            origin: PresentationOrigin(.madeHere, detail: "Bible passage builder")
        )
        controls.fire(slide: slides[0], in: presentation)
    }

    private func biblePresentationID(for verse: BibleXMLImporter.Verse) -> String {
        "bible-live:\(englishVersionID):\(verse.book):\(verse.chapter):\(verse.number)"
    }

    private func activateLowerThirdOutput() {
        guard let controls, let presets, !lowerThirdThemeID.isEmpty else { return }
        lowerThirdWorking = true
        Task { @MainActor in
            defer { lowerThirdWorking = false }
            await model.themesFilled([lowerThirdThemeID])
            do {
                _ = try NDIScreenOutputs.shared.configureLowerThird(
                    themeID: lowerThirdThemeID, render: controls.render
                )
                presets.applyActivePreset()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func stopLowerThirdOutput() {
        guard let controls, let presets else { return }
        lowerThirdWorking = true
        NDIScreenOutputs.shared.disableLowerThird(render: controls.render)
        presets.applyActivePreset()
        lowerThirdWorking = false
    }

    private func makeSlide(
        for verse: BibleXMLImporter.Verse,
        sectionID: String,
        tamil: BibleXMLImporter.Verse?
    ) -> Slide {
        let superscriptNumber = Self.superscriptNumber(verse.number)
        let text = [
            "\(superscriptNumber) \(verse.text)",
            tamil.map { "\(superscriptNumber) \($0.text)" },
        ].compactMap { $0 }.joined(separator: "\n\n")
        let reference = SlideObject(
            id: UUID().uuidString,
            objectKind: .text,
            name: "Bible Reference",
            text: "\(verse.book) \(verse.chapter):\(verse.number)",
            x: 200,
            y: 55,
            width: 1520,
            height: 85,
            textStyle: TextStyle(
                fontSize: 34,
                horizontalAlignment: .center,
                verticalAlignment: .middle,
                autoShrink: true,
                minFontSize: 24
            )
        )
        let scripture = SlideObject(
            id: UUID().uuidString,
            objectKind: .text,
            name: "Scripture",
            text: text,
            x: 200,
            y: 150,
            width: 1520,
            height: 790,
            textStyle: TextStyle(
                lineHeightMultiple: 1.12,
                horizontalAlignment: .center,
                verticalAlignment: .middle,
                autoShrink: true,
                minFontSize: 24
            )
        )
        var versionLabels: [String] = []
        if let englishVersion {
            versionLabels.append(shortVersionName(englishVersion))
        }
        if tamil != nil, let tamilVersion {
            versionLabels.append(shortVersionName(tamilVersion))
        }
        let versionNames = versionLabels.joined(separator: "  ·  ")
        let versions = SlideObject(
            id: UUID().uuidString,
            objectKind: .text,
            name: "Bible Versions",
            text: versionNames.isEmpty ? "" : versionNames,
            x: 200,
            y: 955,
            width: 1520,
            height: 70,
            textStyle: TextStyle(
                fontSize: 28,
                horizontalAlignment: .center,
                verticalAlignment: .middle,
                autoShrink: true,
                minFontSize: 18
            )
        )
        var slide = Slide(
            id: UUID().uuidString,
            name: "\(verse.book) \(verse.chapter):\(verse.number)",
            objects: [reference, scripture, versions]
        )
        slide.sectionId = sectionID
        slide.themeSlideName = model.slideBuilding.lyricsDesign
        return slide
    }

    private static func superscriptNumber(_ number: Int) -> String {
        let superscriptDigits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        ]
        return String(String(number).map { superscriptDigits[$0] ?? $0 })
    }
}
