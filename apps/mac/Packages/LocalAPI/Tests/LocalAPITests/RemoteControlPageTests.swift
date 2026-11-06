import Testing
@testable import LocalAPI

struct RemoteControlPageTests {
    @Test func remoteProvidesOnlyShowNavigationAndVerseReturnControls() {
        let html = RemoteControlPage.html

        #expect(html.contains("Chorus Remote"))
        #expect(html.contains("/v1/show/advance"))
        #expect(html.contains("/v1/show/return-underlying"))
        #expect(html.contains("Go back to the slide"))
        #expect(html.contains("min-height: 88px"))
        #expect(!html.contains("/v1/show/clear-all"))
        #expect(!html.contains("/v1/show/clear'"))
        #expect(!html.contains("id=\"connect\""))
        #expect(!html.contains("<script src="))
        #expect(!html.contains("https://"))
    }
}
