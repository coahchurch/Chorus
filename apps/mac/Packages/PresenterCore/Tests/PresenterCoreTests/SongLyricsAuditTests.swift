import Foundation
import Testing
@testable import PresenterCore

struct SongLyricsAuditTests {
    @Test func detectsEmptyLyricsAndUnbalancedBilingualLines() {
        let slides = [
            Slide(id: "empty", name: "Empty", objects: []),
            Slide(id: "lyrics", name: "Verse", objects: [
                SlideObject(
                    id: "text", objectKind: .text, name: "Lyrics",
                    text: "தமிழ் ஒன்று\nதமிழ் இரண்டு\nதமிழ் மூன்று\nதமிழ் நான்கு\nEnglish one\nEnglish two"
                ),
            ]),
        ]
        let presentation = Presentation(
            id: "song", name: "Song", presentationKind: .song, themeId: "", slides: slides
        )

        #expect(SongLyricsAudit.inspect(presentation).map(\.kind) == [
            .emptySlide, .unbalancedLanguageLines,
        ])
    }

    @Test func ignoresBalancedBilingualSlidesAndNonSongDecks() {
        let slide = Slide(id: "lyrics", name: "Verse", objects: [
            SlideObject(
                id: "text", objectKind: .text, name: "Lyrics",
                text: "தமிழ் ஒன்று\nதமிழ் இரண்டு\nEnglish one\nEnglish two"
            ),
        ])
        let song = Presentation(
            id: "song", name: "Song", presentationKind: .song, themeId: "", slides: [slide]
        )
        let deck = Presentation(
            id: "deck", name: "Deck", presentationKind: .deck, themeId: "", slides: [slide]
        )

        #expect(SongLyricsAudit.inspect(song).isEmpty)
        #expect(SongLyricsAudit.inspect(deck).isEmpty)
    }

    @Test func presentationTagsAreOptionalForExistingFiles() throws {
        let presentation = Presentation(
            id: "song", name: "Song", presentationKind: .song,
            themeId: "", slides: [], tags: ["Tamil", "Worship"]
        )
        #expect(presentation.indexText.contains("Tamil"))
        #expect(presentation.indexText.contains("Worship"))
        let encoded = try JSONEncoder().encode(presentation)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "tags")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Presentation.self, from: oldData)

        #expect(decoded.tags == nil)
    }
}
