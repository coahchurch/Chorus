import Foundation
import Testing
@testable import PresenterCore

struct SongLyricsTests {
    @Test func sourceCodableStoresLyricsWithoutSlidesAndProjectsDeterministically() throws {
        let song = SongLyrics(
            id: "song-1",
            name: "Tamil Song",
            author: "Author",
            key: "D",
            ccliNumber: 12345,
            parts: [
                SongLyricsPart(
                    id: "verse-1",
                    label: "Verse 1",
                    primaryLines: ["தமிழ் ஒன்று", "தமிழ் இரண்டு"],
                    transliterationLines: ["tamil ondru", "tamil irandu"]
                ),
            ],
            folder: "Hymns",
            folderId: "hymns-folder"
        )
        let data = try JSONEncoder().encode(song)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(SongLyrics.self, from: data)

        #expect(decoded == song)
        #expect(!json.contains("\"slides\""))

        let first = decoded.presentation(linesPerSlide: 1)
        let second = decoded.presentation(linesPerSlide: 1)
        _ = decoded.presentation(linesPerSlide: 4)
        #expect(first.id == "song-lyrics:song-1")
        #expect(first.slides.map(\.id) == second.slides.map(\.id))
        #expect(first.slides.flatMap(\.objects).map(\.id) == second.slides.flatMap(\.objects).map(\.id))
        #expect(first.sections?.map(\.name) == ["Verse 1"])
        #expect(first.slides.allSatisfy { !$0.objects.isEmpty })
        #expect(first.arrangements == nil)
        #expect(first.ccli?.songNumber == 12345)
        #expect(first.musicKey == "D")
        #expect(first.presentationKind == .song)
        #expect(first.indexTag == "song")
        #expect(first.transliterationSource?.contains("tamil ondru") == true)
        #expect(decoded.parts[0].primaryLines == ["தமிழ் ஒன்று", "தமிழ் இரண்டு"])
        #expect(decoded.parts[0].transliterationLines == ["tamil ondru", "tamil irandu"])
        #expect(decoded.folder == "Hymns")
        #expect(decoded.folderId == "hymns-folder")
        #expect(decoded.indexSubkind == "Hymns")
        #expect(decoded.indexFolderId == "hymns-folder")
        #expect(decoded == song)
    }

    @Test func pairedReflowKeepsBlankTranslationRowsAligned() {
        let parsed = Reflow.parsePaired(
            "{c: Verse 1}\nprimary one\nprimary two\nprimary three",
            transliteration: "{c: Verse 1}\ntrans one\n\ntrans three",
            linesPerSlide: 2
        )

        #expect(parsed.sections.map(\.name) == ["Verse 1"])
        #expect(parsed.sections[0].slides == [
            "primary one\nprimary two\n\ntrans one\n",
            "primary three\n\ntrans three",
        ])
    }

    @Test func songProjectionKeepsAnActualIntroButAddsNoBlankOpening() {
        let song = SongLyrics(
            name: "Song with Intro",
            parts: [
                SongLyricsPart(label: "Intro", primaryLines: ["Come and worship"]),
                SongLyricsPart(label: "Verse 1", primaryLines: ["Amazing grace"]),
            ]
        )

        let presentation = song.presentation()

        #expect(presentation.sections?.map(\.name) == ["Intro", "Verse 1"])
        #expect(presentation.slides.first?.objects.first?.text == "Come and worship")
        #expect(presentation.slides.allSatisfy { !$0.objects.isEmpty })
    }

    @Test func pairedReflowKeepsUntranslatedSlidesCompact() {
        let parsed = Reflow.parsePaired(
            "{c: Verse 1}\nதமிழ் ஒன்று\nதமிழ் இரண்டு\nதமிழ் மூன்று\nதமிழ் நான்கு",
            transliteration: "{c: Verse 1}\none\ntwo",
            linesPerSlide: 2
        )

        #expect(parsed.sections[0].slides == [
            "தமிழ் ஒன்று\nதமிழ் இரண்டு\n\none\ntwo",
            "தமிழ் மூன்று\nதமிழ் நான்கு",
        ])
    }

    @Test func presentationHonorsConfiguredMaximumLyricsPerSlide() {
        let song = SongLyrics(
            name: "10,000 Reasons",
            parts: [
                SongLyricsPart(
                    label: "Chorus 1",
                    primaryLines: [
                        "Bless the Lord, O my soul,", "O my soul,",
                        "Worship His holy name", "Sing like never before,",
                        "O my soul,", "I'll worship Your holy name",
                    ]
                ),
                SongLyricsPart(
                    label: "Verse 1",
                    primaryLines: [
                        "The sun comes up, it's a new day dawning;",
                        "It's time to sing Your song again",
                        "Whatever may pass, and whatever lies before me,",
                        "Let me be singing when the evening comes.",
                    ]
                ),
            ]
        )

        let slides = song.presentation(linesPerSlide: 4).slides.filter { !$0.objects.isEmpty }
        let lyricLines = slides.map { slide in
            slide.objects.flatMap { $0.text.components(separatedBy: .newlines) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        #expect(lyricLines.map(\.count) == [4, 2, 4])
    }

    @Test func convertsOpenLyricsSectionsAndLinePairsIntoSourceParts() throws {
        let xml = """
        <song>
          <properties>
            <titles><title>Paired Song</title></titles>
            <authors><author>Author</author></authors>
            <key>D</key>
            <ccliNo>6789</ccliNo>
          </properties>
          <lyrics>
            <verse name="v1">
              <lines lang="ta" script="Taml">தமிழ் ஒன்று
        தமிழ் இரண்டு</lines>
              <lines lang="ta" script="Latn">tamil ondru
        tamil irandu</lines>
            </verse>
            <chorus name="c">
              <lines lang="ta" script="Taml">தமிழ் மூன்று</lines>
              <lines lang="ta" script="Latn">tamil moondru</lines>
            </chorus>
          </lyrics>
        </song>
        """
        let parsed = try OpenLyricsImporter.parse(Data(xml.utf8))
        let song = SongLyrics.openLyrics(parsed)

        #expect(song.name == "Paired Song")
        #expect(song.parts.map(\.label) == ["Verse 1", "Chorus"])
        #expect(song.parts[0].primaryLines == ["தமிழ் ஒன்று", "தமிழ் இரண்டு"])
        #expect(song.parts[0].transliterationLines == ["tamil ondru", "tamil irandu"])
        #expect(song.parts[1].primaryLines == ["தமிழ் மூன்று"])
        #expect(song.parts[1].transliterationLines == ["tamil moondru"])
        #expect(song.key == "D")
        #expect(song.ccliNumber == 6789)
    }

    @Test func pastedTextPairsPartsByLabelWithoutPersistingSlideCounts() {
        let song = SongLyrics.pasted(
            name: "Pasted",
            primaryText: "{c: Verse 1}\nதமிழ் ஒன்று\nதமிழ் இரண்டு\n\n{c: Chorus}\nதமிழ் மூன்று",
            transliterationText: "{c: Verse 1}\ntamil ondru\ntamil irandu\n\n{c: Chorus}\ntamil moondru"
        )

        #expect(song.parts.map(\.label) == ["Verse 1", "Chorus"])
        #expect(song.parts[0].transliterationLines == ["tamil ondru", "tamil irandu"])
        #expect(song.parts[1].transliterationLines == ["tamil moondru"])
    }

    @Test func pastedParagraphsBecomeSeparateVersesAndLineBreaksStayWithinVerses() {
        let song = SongLyrics.pasted(
            name: "Pasted",
            primaryText: "First verse, line one\r\nFirst verse, line two\r\n\r\nSecond verse, line one\r\nSecond verse, line two"
        )

        #expect(song.parts.map(\.label) == ["Verse 1", "Verse 2"])
        #expect(song.parts[0].primaryLines == ["First verse, line one", "First verse, line two"])
        #expect(song.parts[1].primaryLines == ["Second verse, line one", "Second verse, line two"])
    }
}
