import PresenterCore
import SwiftUI

struct SongReviewView: View {
    let model: AppModel
    let presentationID: String

    @Environment(\.dismiss) private var dismiss
    @State private var presentation: Presentation?
    @State private var tagsText = ""
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    private var duplicateTitles: [LibraryIndex.Entry] {
        guard let presentation else { return [] }
        let target = normalized(presentation.name)
        return model.entries(of: .presentation).filter {
            $0.id != presentation.id && normalized($0.name) == target
        }
    }

    private var issues: [SongLyricsAudit.Issue] {
        guard let presentation else { return [] }
        return SongLyricsAudit.inspect(presentation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Song Review", systemImage: "checkmark.seal")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if loading {
                ProgressView("Loading song…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let presentation {
                Form {
                    Section("Library Tags") {
                        TextField("Comma-separated tags", text: $tagsText)
                        Text("Tags are included in library search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Bilingual Lyrics") {
                        if presentation.presentationKind != .song {
                            Text("This presentation is a deck, not a song.")
                                .foregroundStyle(.secondary)
                        } else if issues.isEmpty {
                            Label("No empty slides or large Tamil/Latin line-count mismatches found.",
                                  systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(issues) { issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.slideName.isEmpty ? "Untitled slide" : issue.slideName)
                                        .font(.subheadline.weight(.medium))
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Duplicate Titles") {
                        if duplicateTitles.isEmpty {
                            Text("No other presentation has this exact title.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(duplicateTitles, id: \.id) { entry in
                                Label(entry.name, systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Could Not Load Song",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            }

            if let errorMessage, presentation != nil {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Save Tags") { saveTags() }
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation == nil || loading || saving)
            }
        }
        .padding(18)
        .frame(width: 560, height: 600)
        .task(id: presentationID) { await loadSong() }
    }

    private func loadSong() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await model.client.loadValue(Presentation.self, id: presentationID)
            presentation = value
            tagsText = (value.tags ?? []).joined(separator: ", ")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTags() {
        let tags = Array(Set(tagsText.split(separator: ",").compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let update = model.updatePresentation(presentationID) {
            $0.tags = tags.isEmpty ? nil : tags
        }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                _ = try await update.value
                await model.client.settled()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
