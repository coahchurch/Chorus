import PresenterCore
import SwiftUI

struct OnlineLyricsImportSheet: View {
    let model: AppModel
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var results: [OnlineLyricsResult] = []
    @State private var lyrics = ""
    @State private var transliteration = ""
    @State private var fetchedTitle = ""
    @State private var isSearching = false
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var editingSlides = false

    var body: some View {
        if editingSlides {
            ReflowSheet(
                importingSongNamed: fetchedTitle.isEmpty ? title : fetchedTitle,
                primaryText: lyrics,
                transliteration: transliteration,
                initialPairsPerSlide: 2,
                onCancel: { editingSlides = false }
            ) { songName, primaryText, transliterationText, linesPerSlide in
                let id = model.createSong(
                    name: songName, primaryText: primaryText,
                    transliterationText: transliterationText, linesPerSlide: linesPerSlide
                )
                onImported(id)
            }
        } else {
            importForm
        }
    }

    private var importForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from online")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Song title", text: $title)
                    .frame(maxWidth: .infinity)
                    .onSubmit(search)
                TextField("Artist (optional)", text: $artist)
                    .frame(maxWidth: .infinity)
                    .onSubmit(search)
                Button("Search") { search() }
                    .disabled(isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !lyrics.isEmpty {
                TextField("Song name", text: $fetchedTitle)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    lyricEditor("Original lyrics", text: $lyrics)
                    lyricEditor("Transliteration", text: $transliteration)
                }
                .frame(minHeight: 260, maxHeight: .infinity)
            } else if isSearching {
                ProgressView("Searching online…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button {
                                fetch(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(result.snippet.isEmpty
                                         ? (result.url.host() ?? result.url.absoluteString)
                                         : result.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if result.id != results.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Search for a song")
                        .font(.body.weight(.medium))
                    Text("Enter a title, and optionally an artist, to find lyrics online.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isFetching {
                ProgressView("Loading lyrics…")
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue to Reflow") { editingSlides = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(
            width: 780,
            height: lyrics.isEmpty ? (results.isEmpty ? 300 : 470) : 680,
            alignment: .top
        )
    }

    private func lyricEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(0)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        isFetching = true
        errorMessage = nil
        Task { @MainActor in
            defer { isFetching = false }
            do {
                let fetched = try await OnlineLyricsImporter.fetchLyrics(from: result.url)
                fetchedTitle = result.title.isEmpty ? (fetched.title ?? title) : result.title
                lyrics = fetched.lyrics
                transliteration = fetched.transliteration
            } catch { errorMessage = error.localizedDescription }
        }
    }

}
