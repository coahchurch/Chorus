import Testing
@testable import LocalAPI

struct RemoteControlPageTests {
    @Test func remoteProvidesTouchControlsWithoutExternalAssets() {
        let html = RemoteControlPage.html

        #expect(html.contains("Chorus Remote"))
        #expect(html.contains("sessionStorage"))
        #expect(html.contains("/v1/show/advance"))
        #expect(html.contains("/v1/show/clear-all"))
        #expect(html.contains("min-height: 58px"))
        #expect(!html.contains("<script src="))
        #expect(!html.contains("https://"))
    }
}
