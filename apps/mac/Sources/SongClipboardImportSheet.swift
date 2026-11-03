import AppKit
import PresenterCore
import SwiftUI

struct SongClipboardImportSheet: View {
    let model: AppModel
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var lyrics = ""
    @State private var transliteration = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Lyrics from Clipboard")
                .font(.headline)
            TextField("Song name", text: $name)
            HStack(spacing: 12) {
                lyricEditor("Original lyrics", text: $lyrics)
                lyricEditor("Transliteration", text: $transliteration)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Paste from Clipboard") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        lyrics = text
                    } else {
                        errorMessage = "The clipboard does not contain text."
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import Song", action: importSong)
                    .keyboardShortcut(.defaultAction)
                    .disabled(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 720, height: 480)
        .onAppear {
            if let text = NSPasteboard.general.string(forType: .string) { lyrics = text }
        }
    }

    private func lyricEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importSong() {
        let fallback = "Untitled Song"
        let song = SongLyrics.pasted(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : name,
            primaryText: lyrics,
            transliterationText: transliteration
        )
        let id = model.createSong(song)
        dismiss()
        onImported(id)
    }
}
