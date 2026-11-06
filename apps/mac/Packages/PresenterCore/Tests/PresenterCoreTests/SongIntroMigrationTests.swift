import Foundation
import Testing
@testable import PresenterCore

@LibraryActor @Test func removesOnlyGeneratedBlankSongOpeningSlides() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try Library(rootURL: root)

    let generated = Presentation(
        id: "generated",
        name: "Generated Opening",
        presentationKind: .song,
        themeId: "",
        slides: [
            Slide(id: "opening", name: "", objects: [], sectionId: "intro", themeSlideName: "Lyrics"),
            Slide(
                id: "verse-slide", name: "", objects: [
                    SlideObject(id: "verse-text", objectKind: .text, name: "Lyrics", text: "Amazing grace"),
                ], sectionId: "verse", themeSlideName: "Lyrics"
            ),
        ],
        sections: [
            PresentationSection(id: "intro", name: "Intro"),
            PresentationSection(id: "verse", name: "Verse 1"),
        ],
        arrangements: [Arrangement(id: "order", name: "As Pasted", sectionIds: ["intro", "verse"])],
        defaultArrangementId: "order",
        reflowSource: "Verse 1\nAmazing grace"
    )
    try library.create(generated)

    let actualIntro = Presentation(
        id: "actual-intro",
        name: "Actual Intro",
        presentationKind: .song,
        themeId: "",
        slides: [
            Slide(
                id: "intro-slide", name: "", objects: [
                    SlideObject(id: "intro-text", objectKind: .text, name: "Lyrics", text: "Come and worship"),
                ], sectionId: "intro", themeSlideName: "Lyrics"
            ),
            Slide(
                id: "actual-verse-slide", name: "", objects: [
                    SlideObject(id: "actual-verse-text", objectKind: .text, name: "Lyrics", text: "Amazing grace"),
                ], sectionId: "verse", themeSlideName: "Lyrics"
            ),
        ],
        sections: [
            PresentationSection(id: "intro", name: "Intro"),
            PresentationSection(id: "verse", name: "Verse 1"),
        ],
        reflowSource: "Intro\nCome and worship\n\nVerse 1\nAmazing grace"
    )
    try library.create(actualIntro)

    let emptyCue = Presentation(
        id: "empty-cue",
        name: "Intentional Empty Cue",
        presentationKind: .song,
        themeId: "",
        slides: [
            Slide(id: "cue", name: "", objects: [], sectionId: "intro", themeSlideName: "Lyrics"),
            Slide(
                id: "cue-verse", name: "", objects: [
                    SlideObject(id: "cue-verse-text", objectKind: .text, name: "Lyrics", text: "Amazing grace"),
                ], sectionId: "verse", themeSlideName: "Lyrics"
            ),
        ],
        sections: [
            PresentationSection(id: "intro", name: "Intro"),
            PresentationSection(id: "verse", name: "Verse 1"),
        ],
        reflowSource: "Intro\n\nVerse 1\nAmazing grace"
    )
    try library.create(emptyCue)

    #expect(try library.removeGeneratedSongIntroSlides() == 1)

    let updated = try library.open(Presentation.self, id: "generated").value
    #expect(updated.slides.map(\.id) == ["verse-slide"])
    #expect(updated.sections?.map(\.id) == ["verse"])
    #expect(updated.arrangements?.first?.sectionIds == ["verse"])

    #expect(try library.open(Presentation.self, id: "actual-intro").value.slides.first?.id == "intro-slide")
    #expect(try library.open(Presentation.self, id: "empty-cue").value.slides.first?.id == "cue")
    #expect(try library.removeGeneratedSongIntroSlides() == 0)
}
