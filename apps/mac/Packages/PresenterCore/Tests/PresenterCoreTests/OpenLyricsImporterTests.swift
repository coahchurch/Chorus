import Foundation
import Testing
@testable import PresenterCore

struct OpenLyricsImporterTests {
    private let document = """
    <?xml version="1.0" encoding="UTF-8"?>
    <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.8">
      <properties>
        <titles><title>King of Glory</title></titles>
        <authors><author>Scott Smith</author><author>Mary Jones</author></authors>
        <publisher>Example Music</publisher>
        <copyright>Copyright 2014 Example Music</copyright>
        <ccliNo>123456</ccliNo>
        <key>D</key>
        <verseOrder>v1 c v2 c</verseOrder>
      </properties>
      <lyrics>
        <verse name="v1"><lines>
          <line>Who is this King of Glory <chord name="D"/>the Lord<br/>strong and mighty</line>
          <line>Who is this King of Glory</line>
        </lines></verse>
        <chorus name="c"><lines>
          <line>Lift up your heads</line>
        </lines></chorus>
        <verse name="v2"><lines>
          <line>Who is this King of Glory <chord name="A"/>the Lord strong and mighty</line>
        </lines></verse>
      </lyrics>
    </song>
    """

    @Test func parsesMetadataChordsAndVerseOrder() throws {
        let song = try OpenLyricsImporter.parse(Data(document.utf8))

        #expect(song.title == "King of Glory")
        #expect(song.authors == ["Scott Smith", "Mary Jones"])
        #expect(song.publisher == "Example Music")
        #expect(song.ccliNumber == 123456)
        #expect(song.musicKey == "D")
        #expect(song.ccli?.songTitle == "King of Glory")
        #expect(song.ccli?.author == "Scott Smith, Mary Jones")
        #expect(song.ccli?.copyrightYear == 2014)

        let parts = song.lyricsText.components(separatedBy: "\n\n")
        #expect(parts.map { $0.components(separatedBy: "\n").first } == [
            "{c: Verse 1}", "{c: Chorus}", "{c: Verse 2}", "{c: Chorus}",
        ])
        #expect(parts[0].contains("Who is this King of Glory [D]the Lord\nstrong and mighty"))
        #expect(parts[2].contains("Who is this King of Glory [A]the Lord strong and mighty"))
    }

    @Test func rejectsUnrelatedAndMalformedXml() {
        #expect(throws: OpenLyricsImporter.ImportError.notOpenLyrics) {
            try OpenLyricsImporter.parse(Data("<document/>".utf8))
        }
        #expect(throws: OpenLyricsImporter.ImportError.self) {
            try OpenLyricsImporter.parse(Data("<song>".utf8))
        }
    }

    @Test func rejectsSongsWithoutLyricSections() {
        let xml = """
        <song xmlns="http://openlyrics.info/namespace/2009/song">
          <properties><titles><title>Empty</title></titles></properties>
          <lyrics/>
        </song>
        """
        #expect(throws: OpenLyricsImporter.ImportError.noLyrics) {
            try OpenLyricsImporter.parse(Data(xml.utf8))
        }
    }

    @Test func importsSongbookCollectionsWithTextInsideLinesElements() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <songbooks>
          <song version="0.8" createdIn="stageflo">
            <properties>
              <titles><title>First Song</title></titles>
              <authors><author>First Author</author></authors>
              <verseOrder>v1</verseOrder>
            </properties>
            <lyrics>
              <verse name="v1">
                <lines lang="en" script="latin">First verse line
        Second verse line</lines>
              </verse>
            </lyrics>
          </song>
          <song version="0.8" createdIn="stageflo">
            <properties><titles><title>Second Song</title></titles></properties>
            <lyrics>
              <verse name="v1">
                <lines lang="en" script="latin">
                  <line>Another first line</line>
                  <line>Another second line</line>
                </lines>
              </verse>
            </lyrics>
          </song>
        </songbooks>
        """

        let songs = try OpenLyricsImporter.parseSongs(Data(xml.utf8))
        #expect(songs.count == 2)
        #expect(songs.map(\.title) == ["First Song", "Second Song"])
        #expect(songs[0].authors == ["First Author"])
        #expect(songs[0].lyricsText.contains("First verse line\nSecond verse line"))
        #expect(songs[1].lyricsText.contains("Another first line\nAnother second line"))
        #expect(throws: OpenLyricsImporter.ImportError.multipleSongs(2)) {
            try OpenLyricsImporter.parse(Data(xml.utf8))
        }
    }

    @Test func separatesTamilLyricsFromLatinTransliteration() throws {
        let xml = """
        <songbooks>
          <song>
            <properties><titles><title>Tamil Song</title></titles></properties>
            <lyrics>
              <verse name="v1">
                <lines lang="ta" script="tamil">தமிழ் முதல் வரி
        தமிழ் இரண்டாம் வரி</lines>
                <lines lang="en" script="latin">tamil mudhal vari
        tamil irandaam vari</lines>
              </verse>
            </lyrics>
          </song>
        </songbooks>
        """

        let song = try #require(OpenLyricsImporter.parseSongs(Data(xml.utf8)).first)
        #expect(song.lyricsText.contains("தமிழ் முதல் வரி\nதமிழ் இரண்டாம் வரி"))
        #expect(song.transliterationText?.contains("tamil mudhal vari\ntamil irandaam vari") == true)
    }

    @Test func recognizesISO15924LatinScriptAndKeepsUnevenVersesAligned() throws {
        let xml = """
        <song>
          <properties><titles><title>Tamil Song</title></titles></properties>
          <lyrics>
            <verse name="v1">
              <lines lang="ta" script="Taml">தமிழ் ஒன்று
        தமிழ் இரண்டு</lines>
              <lines lang="ta" script="Latn">one</lines>
            </verse>
            <verse name="v2">
              <lines lang="ta" script="Taml">தமிழ் மூன்று
        தமிழ் நான்கு</lines>
              <lines lang="ta" script="Latn">three
        four</lines>
            </verse>
          </lyrics>
        </song>
        """

        let song = try OpenLyricsImporter.parse(Data(xml.utf8))
        #expect(song.transliterationText?.contains("{c: Verse 1}\none") == true)
        #expect(song.transliterationText?.contains("{c: Verse 2}\nthree\nfour") == true)

        let presentation = LyricTextImporter.makePresentation(
            song.lyricsText,
            linesPerSlide: 2,
            transliteration: song.transliterationText
        )
        let lyricSlides = presentation.slides.compactMap { slide -> String? in
            guard let text = slide.objects.first?.text, text.contains("தமிழ்") else { return nil }
            return text
        }
        #expect(lyricSlides.count == 2)
        #expect(lyricSlides[0].contains("one"))
        #expect(!lyricSlides[0].contains("three"))
        #expect(lyricSlides[1].contains("three"))
        #expect(lyricSlides[1].contains("four"))
        #expect(!lyricSlides[1].contains("one"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MXU_OPENLYRICS_SONGBK"] != nil))
    func importsProvidedSongbookFixture() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MXU_OPENLYRICS_SONGBK"])
        let songs = try OpenLyricsImporter.parseSongs(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(songs.count > 1)
        #expect(songs.allSatisfy { !$0.lyricsText.isEmpty })
        #expect(songs.contains { $0.transliterationText != nil })
        for song in songs where song.transliterationText != nil {
            #expect(
                LyricTextImporter.lyricLineCount(song.lyricsText)
                    == LyricTextImporter.lyricLineCount(song.transliterationText ?? ""),
                "The source lyric and transliteration lines should align for \(song.title ?? "untitled")"
            )
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MXU_ENGLISH_OPENLYRICS_SONGBK"] != nil))
    func importsEnglishSongbookVerseBlocks() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MXU_ENGLISH_OPENLYRICS_SONGBK"])
        let songs = try OpenLyricsImporter.parseSongs(Data(contentsOf: URL(fileURLWithPath: path)))
        let source = try #require(songs.first { $0.title?.hasPrefix("I know that my Redeemer lives") == true })
        let song = SongLyrics.openLyrics(source)

        #expect(song.parts.map(\.label) == ["Verse 1", "Verse 2", "Verse 3", "Verse 4", "Verse 5"])
        #expect(song.parts.allSatisfy { !$0.primaryLines.isEmpty })
        #expect(song.parts[0].primaryLines == [
            "I know that my Redeemer lives; What comfort this sweet sentence gives! He lives, He lives, who once was dead; He lives, my ever living Head."
        ])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MXU_ENGLISH_OPENLYRICS_SONGBK"] != nil))
    func fourLineSettingProducesFourEnglishLyricsPerSlide() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MXU_ENGLISH_OPENLYRICS_SONGBK"])
        let songs = try OpenLyricsImporter.parseSongs(Data(contentsOf: URL(fileURLWithPath: path)))
        let source = try #require(songs.first { $0.title == "10,000 Reasons" })
        let slides = SongLyrics.openLyrics(source).presentation(linesPerSlide: 4).slides
        let lyricLineCounts = slides.filter { !$0.objects.isEmpty }.map { slide in
            slide.objects.flatMap { $0.text.components(separatedBy: .newlines) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
        }

        #expect(lyricLineCounts == [4, 2, 4, 4, 4])
    }
}
