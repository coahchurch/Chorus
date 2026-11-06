import Foundation
import Testing
@testable import PresenterCore

struct BibleXMLImporterTests {

    @Test func importsZefaniaBibleAndUsesBookNumbersForTamilAlignment() throws {
        let xml = """
        <XMLBIBLE biblename="English">
          <BIBLEBOOK bnumber="1" bname="Genesis">
            <CHAPTER cnumber="1">
              <VERS vnumber="1">In the beginning God created the heaven and the earth.</VERS>
              <VERS vnumber="2">And the earth was without form.</VERS>
            </CHAPTER>
          </BIBLEBOOK>
        </XMLBIBLE>
        """

        let version = try BibleXMLImporter.parse(
            Data(xml.utf8), versionName: "English", sourceName: "english.xml"
        )
        #expect(version.books == ["Genesis"])
        #expect(version.verses.map(\.id) == ["Genesis|1|1", "Genesis|1|2"])
        #expect(version.verses.first?.text == "In the beginning God created the heaven and the earth.")
    }

    @Test func importsOSISBookChapterAndVerseMilestones() throws {
        let xml = """
        <osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace">
          <osisText><div type="book" osisID="John">
            <chapter osisID="John.3">
              <verse osisID="John.3.16">For God so loved the world.</verse>
            </chapter>
          </div></osisText>
        </osis>
        """

        let version = try BibleXMLImporter.parse(
            Data(xml.utf8), versionName: "English", sourceName: "osis.xml"
        )
        #expect(version.verses == [
            BibleXMLImporter.Verse(
                book: "John", bookNumber: nil, chapter: 3, number: 16,
                text: "For God so loved the world."
            ),
        ])
    }

    @Test func pairsTamilAndEnglishByCanonicalVerseReference() throws {
        let english = """
        <XMLBIBLE><BIBLEBOOK bnumber="43" bname="John"><CHAPTER cnumber="3">
          <VERS vnumber="16">For God so loved the world.</VERS>
        </CHAPTER></BIBLEBOOK></XMLBIBLE>
        """
        let tamil = """
        <XMLBIBLE><BIBLEBOOK bnumber="43" bname="யோவான்"><CHAPTER cnumber="3">
          <VERS vnumber="16">தேவன் உலகத்தில் அன்புகூர்ந்தார்.</VERS>
        </CHAPTER></BIBLEBOOK></XMLBIBLE>
        """
        let en = try BibleXMLImporter.parse(Data(english.utf8), versionName: "EN", sourceName: "en.xml")
        let ta = try BibleXMLImporter.parse(Data(tamil.utf8), versionName: "TA", sourceName: "ta.xml")

        #expect(en.verses.first?.id == ta.verses.first?.id)
        #expect(en.books == ["John"])
        #expect(ta.books == ["John"])
    }

    @Test func normalizesCommonBookAliasesAndNumberedBooks() {
        #expect(BibleXMLImporter.canonicalBookName("Gen") == "Genesis")
        #expect(BibleXMLImporter.canonicalBookName("1Cor") == "1 Corinthians")
        #expect(BibleXMLImporter.canonicalBookName("Tamil Book", bookNumber: 43) == "John")
    }

    @Test func ordersBooksByBookNumberRegardlessOfVerseOrder() {
        let version = BibleXMLImporter.Version(
            id: "english", name: "English", sourceName: "english.xml", verses: [
                BibleXMLImporter.Verse(
                    book: "Exodus", bookNumber: 2, chapter: 1, number: 1, text: "..."
                ),
                BibleXMLImporter.Verse(
                    book: "Genesis", bookNumber: 1, chapter: 1, number: 1, text: "..."
                ),
            ]
        )

        #expect(version.books == ["Genesis", "Exodus"])
    }

    @Test func decodesSavedVersionsWithoutOptionalCopyrightMetadata() throws {
        let version = BibleXMLImporter.Version(
            id: "legacy", name: "English", sourceName: "english.xml",
            verses: [
                BibleXMLImporter.Verse(
                    book: "Genesis", bookNumber: 1, chapter: 1, number: 1, text: "Verse"
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(version)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "copyright")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BibleXMLImporter.Version.self, from: legacyData)
        #expect(decoded.copyright == nil)
        #expect(decoded.verses == version.verses)
    }

    @Test func searchesAcrossVersionsCaseInsensitivelyAndHonorsLimit() {
        let verse = BibleXMLImporter.Verse(
            book: "John", bookNumber: nil, chapter: 3, number: 16,
            text: "For God so loved the world."
        )
        let versions = [
            BibleXMLImporter.Version(
                id: "english", name: "English", sourceName: "english.xml", verses: [verse]
            ),
            BibleXMLImporter.Version(
                id: "second", name: "Second", sourceName: "second.xml", verses: [verse]
            ),
        ]

        let results = BibleXMLImporter.search(versions: versions, query: "LOVED", limit: 1)

        #expect(results.count == 1)
        #expect(results.first?.versionID == "english")
        #expect(results.first?.verse.id == verse.id)
        #expect(BibleXMLImporter.search(versions: versions, query: "missing").isEmpty)
    }

    @Test func searchRecognizesBibleReferencesAndVerseRanges() {
        let verses = [
            BibleXMLImporter.Verse(
                book: "Esther", bookNumber: 17, chapter: 8, number: 8, text: "Write this."
            ),
            BibleXMLImporter.Verse(
                book: "Esther", bookNumber: 17, chapter: 8, number: 9, text: "Send the letter."
            ),
            BibleXMLImporter.Verse(
                book: "Esther", bookNumber: 17, chapter: 8, number: 10, text: "Seal the letter."
            ),
        ]
        let version = BibleXMLImporter.Version(
            id: "english", name: "English", sourceName: "english.xml", verses: verses
        )

        #expect(BibleXMLImporter.search(versions: [version], query: "esther 8:9").map(\.verse.number) == [9])
        #expect(BibleXMLImporter.search(versions: [version], query: "Esth 8:8-9").map(\.verse.number) == [8, 9])
        #expect(BibleXMLImporter.search(versions: [version], query: "Esther 8").map(\.verse.number) == [8, 9, 10])
    }

    @Test func extractsOrderedReferencesIncludingChapterAndCrossChapterRanges() {
        let references = BibleXMLImporter.references(
            in: "See Jn. 3:16–18, then 1 John 4 and Romans 8:28–9:2."
        )

        #expect(references.map(\.displayName) == [
            "John 3:16–18",
            "1 John 4",
            "Romans 8:28–9:2",
        ])
        #expect(references.map(\.book) == ["John", "1 John", "Romans"])
        #expect(references[0].verses == 16...18)
        #expect(references[1].verses == nil)
        #expect(references[2].chapter == 8)
        #expect(references[2].verses == 28...28)
        #expect(references[2].endChapter == 9)
        #expect(references[2].endVerse == 2)
    }

    @Test func extractsShorthandVerseListsAndPeriodEndedAbbreviations() {
        let references = BibleXMLImporter.references(in: "Jn. 3:16, 18–20")

        #expect(references.map(\.displayName) == ["John 3:16", "John 3:18–20"])
    }

    @Test func extractsChapterRangesAndDoesNotMatchBooksInsideWords() {
        let references = BibleXMLImporter.references(
            in: "Matthew 5–7. Not a reference: Johnathan 3:16."
        )

        #expect(references.map(\.displayName) == ["Matthew 5–7"])
    }

    @Test func resolvesWholeChapterAndCrossChapterPassagesInVerseOrder() {
        let version = BibleXMLImporter.Version(
            id: "english", name: "English", sourceName: "english.xml", verses: [
                .init(book: "John", bookNumber: 43, chapter: 4, number: 2, text: "four two"),
                .init(book: "John", bookNumber: 43, chapter: 3, number: 17, text: "three seventeen"),
                .init(book: "John", bookNumber: 43, chapter: 3, number: 16, text: "three sixteen"),
                .init(book: "John", bookNumber: 43, chapter: 4, number: 1, text: "four one"),
            ]
        )
        let references = BibleXMLImporter.references(
            in: "John 3:16–4:2; John 4"
        )

        #expect(BibleXMLImporter.verses(for: references[0], in: version)?.map(\.id) == [
            "John|3|16", "John|3|17", "John|4|1", "John|4|2",
        ])
        #expect(BibleXMLImporter.verses(for: references[1], in: version)?.map(\.id) == [
            "John|4|1", "John|4|2",
        ])
    }

    @Test func doesNotResolveRangesWithUnavailableEndpoints() throws {
        let version = BibleXMLImporter.Version(
            id: "english", name: "English", sourceName: "english.xml", verses: [
                .init(book: "John", bookNumber: 43, chapter: 3, number: 16, text: "...")
            ]
        )
        let reference = try #require(BibleXMLImporter.references(in: "John 3:16–18").first)

        #expect(BibleXMLImporter.verses(for: reference, in: version) == nil)
    }

    @Test func rejectsUnrecognizedXmlAndEmptyBible() {
        #expect(throws: BibleXMLImporter.ImportError.noVerses) {
            try BibleXMLImporter.parse(
                Data("<XMLBIBLE/>".utf8), versionName: "Empty", sourceName: "empty.xml"
            )
        }
        #expect(throws: BibleXMLImporter.ImportError.self) {
            try BibleXMLImporter.parse(
                Data("<not xml".utf8), versionName: "Invalid", sourceName: "bad.xml"
            )
        }
    }
}
