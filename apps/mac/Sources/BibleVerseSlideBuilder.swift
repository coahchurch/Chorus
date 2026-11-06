import Foundation
import PresenterCore

enum BibleVerseSlideBuilder {
    static let liveVerseOrigin = "Bible XML live verse"

    static func shortVersionName(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("tamil") { return "TAM" }
        let parts = name.split { !$0.isLetter && !$0.isNumber }
        if let abbreviation = parts.last, abbreviation.count <= 6 {
            return abbreviation.uppercased()
        }
        return name
    }

    static func makePresentation(
        for verse: BibleXMLImporter.Verse,
        versionName: String,
        themeSlideName: String
    ) -> Presentation {
        let slide = makeSlide(
            for: verse,
            sectionID: "bible-\(verse.book)-\(verse.chapter)",
            versionName: versionName,
            themeSlideName: themeSlideName
        )
        return Presentation(
            id: UUID().uuidString,
            name: "\(verse.book) \(verse.chapter):\(verse.number)",
            presentationKind: .deck,
            themeId: "",
            slides: [slide],
            origin: PresentationOrigin(.madeHere, detail: liveVerseOrigin)
        )
    }

    static func makeSlide(
        for verse: BibleXMLImporter.Verse,
        sectionID: String,
        tamil: BibleXMLImporter.Verse? = nil,
        versionName: String,
        tamilVersionName: String? = nil,
        themeSlideName: String
    ) -> Slide {
        let superscriptNumber = superscriptNumber(verse.number)
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
        let versionLabels = [versionName, tamil == nil ? nil : tamilVersionName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
        let versions = SlideObject(
            id: UUID().uuidString,
            objectKind: .text,
            name: "Bible Versions",
            text: versionLabels,
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
        slide.themeSlideName = themeSlideName
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
