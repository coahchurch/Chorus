import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportOpenLyricsSheet: View {
    let model: AppModel
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadedFiles: [LoadedFile] = []
    @State private var loadErrors: [String] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var loadedSongCount = 0
    @State private var loadedHasTransliteration = false
    @State private var includeTransliteration = true

    private struct LoadedFile: Identifiable, Sendable {
        var id: String { name }
        var name: String
        var songs: [OpenLyricsImporter.Song]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import OpenLyrics Songs")
                .font(.headline)

            Text("Choose OpenLyrics song files or songbooks. Imported songs remain lyric-only library documents.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Choose XML Files…", action: chooseFiles)
                    .disabled(isLoading || isImporting)
                if isLoading { ProgressView().controlSize(.small) }
                Text(loadedSongCount == 0 ? "No files loaded" : "\(loadedSongCount) songs loaded")
                    .foregroundStyle(.secondary)
            }

            if isImporting {
                ProgressView(value: Double(importProgress), total: Double(max(loadedSongCount, 1)))
                Text("Importing \(importProgress) of \(loadedSongCount) songs…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if loadedSongCount > 0 {
                if loadedHasTransliteration {
                    Toggle("Include Latin transliteration where available", isOn: $includeTransliteration)
                        .disabled(isImporting)
                }

                Text("Original lyrics and transliteration are stored as paired lines; presentation slides are generated only while presenting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !loadErrors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(loadErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isImporting)
                Button(isImporting ? "Importing…" : "Import \(loadedSongCount) Songs", action: importSongs)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loadedSongCount == 0 || isLoading || isImporting)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }

    private func chooseFiles() {
        guard let window = NSApp.keyWindow else {
            loadErrors = ["The XML file chooser could not attach to this window. Close this sheet and try again."]
            return
        }
        guard let xmlType = UTType(filenameExtension: "xml") else {
            loadErrors = ["This Mac could not resolve the XML file type."]
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [xmlType]
        panel.message = "Choose OpenLyrics XML files or songbooks"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            loadFiles(panel.urls)
        }
    }

    private func loadFiles(_ urls: [URL]) {
        isLoading = true
        loadErrors = []
        Task { @MainActor in
            defer { isLoading = false }
            let result = await Task.detached(priority: .userInitiated) {
                var files: [LoadedFile] = []
                var errors: [String] = []
                for url in urls {
                    let hasScopedAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasScopedAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    do {
                        let parsed = try OpenLyricsImporter.parseSongs(Data(contentsOf: url))
                        files.append(LoadedFile(name: url.lastPathComponent, songs: parsed))
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (files, errors)
            }.value
            loadedFiles = result.0
            loadErrors = result.1
            loadedSongCount = result.0.reduce(0) { $0 + $1.songs.count }
            loadedHasTransliteration = result.0.contains { file in
                file.songs.contains { $0.transliterationText != nil }
            }
        }
    }

    private func importSongs() {
        isImporting = true
        importProgress = 0
        Task { @MainActor in
            var ids: [String] = []
            var failures: [String] = []
            var completed = 0
            for file in loadedFiles {
                let offset = completed
                let result = await model.importOpenLyricsSongs(
                    file.songs,
                    sourceName: file.name,
                    linesPerSlide: 4,
                    includeTransliteration: includeTransliteration,
                    onProgress: { count, _ in importProgress = offset + count }
                )
                ids += result.ids
                failures += result.failures
                completed += file.songs.count
            }
            var summary = "Imported \(ids.count) OpenLyrics song\(ids.count == 1 ? "" : "s")"
            if !failures.isEmpty {
                summary += " — \(failures.count) failed: \(failures.prefix(3).joined(separator: "; "))"
            }
            model.noteImportSummary(summary)
            await model.client.settled()
            dismiss()
            if let id = ids.first { onImported(id) }
        }
    }
}
