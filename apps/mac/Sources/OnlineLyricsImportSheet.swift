import PresenterCore
import SwiftUI

struct OnlineLyricsImportSheet: View {
    let model: AppModel
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var results: [OnlineLyricsResult] = []
    @State private var selected: OnlineLyricsResult?
    @State private var lyrics = ""
    @State private var fetchedTitle = ""
    @State private var isSearching = false
    @State private var isFetching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from online").font(.headline)
            HStack {
                TextField("Song title", text: $title)
                TextField("Artist (optional)", text: $artist)
                Button("Search") { search() }
                    .disabled(isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isSearching { ProgressView("Searching…") }
            if !results.isEmpty {
                List(results) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title).font(.body.weight(.medium))
                        Text(result.url.host() ?? result.url.absoluteString)
                            .font(.caption).foregroundStyle(.secondary)
                        if !result.snippet.isEmpty {
                            Text(result.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { fetch(result) }
                }
                .frame(minHeight: 130, maxHeight: 220)
            }
            if isFetching { ProgressView("Loading lyrics…") }
            if !lyrics.isEmpty {
                TextField("Song name", text: $fetchedTitle)
                TextEditor(text: $lyrics)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import Song") { importSong() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 720, height: 560)
    }

    private func search() {
        isSearching = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSearching = false }
            do {
                results = try await OnlineLyricsImporter.search(title: title, artist: artist)
                if results.isEmpty { errorMessage = "No online results were found." }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func fetch(_ result: OnlineLyricsResult) {
        selected = result
        isFetching = true
        errorMessage = nil
        Task { @MainActor in
            defer { isFetching = false }
            do {
                let fetched = try await OnlineLyricsImporter.fetchLyrics(from: result.url)
                fetchedTitle = title.isEmpty ? (fetched.title ?? result.title) : title
                lyrics = fetched.lyrics
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func importSong() {
        let song = SongLyrics.pasted(
            name: fetchedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : fetchedTitle,
            primaryText: lyrics
        )
        let id = model.createSong(song)
        dismiss()
        onImported(id)
    }
}
