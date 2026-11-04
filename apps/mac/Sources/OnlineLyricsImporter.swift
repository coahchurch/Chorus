import Foundation
import SwiftSoup

struct OnlineLyricsResult: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let snippet: String
}

enum OnlineLyricsImporter {
    static func search(title: String, artist: String) async throws -> [OnlineLyricsResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        let query = [title, artist].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { throw ImportError.emptyQuery }
        components.queryItems = [URLQueryItem(name: "q", value: "\(query) lyrics")]

        var request = URLRequest(url: components.url!)
        request.setValue("Chorus/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        let results: [OnlineLyricsResult] = try document.select("a.result__a").compactMap { link in
            guard let url = resultURL(from: try link.attr("href")) else { return nil }
            let resultTitle = try link.text()
            let result = link.parent()?.parent()
            let snippet = try result?.select(".result__snippet").first()?.text() ?? ""
            return OnlineLyricsResult(
                id: url.absoluteString,
                title: resultTitle,
                url: url,
                snippet: snippet
            )
        }
        return results
            .sorted { isGenius($0.url) && !isGenius($1.url) }
            .prefix(8)
            .map { $0 }
    }

    static func fetchLyrics(from url: URL) async throws -> (title: String?, lyrics: String) {
        var request = URLRequest(url: url)
        request.setValue("Chorus/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), url.absoluteString)
        let title = try document.select("h1, title").first()?.text()
        let selectors = [
            "[data-lyrics-container=true]",
            ".songLyricsV2",
            ".lyrics"
        ]
        for selector in selectors {
            let elements = try document.select(selector)
            for element in elements {
                let text = try preservedText(in: element)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { line in
                        let lowered = line.lowercased()
                        return !lowered.contains("contributor") && lowered != "lyrics"
                    }
                    .joined(separator: "\n")
                if text.count >= 20 {
                    return (title, isGenius(url) ? removingBracketedText(from: text) : text)
                }
            }
        }
        throw ImportError.lyricsNotFound
    }

    private static func preservedText(in node: Node) throws -> String {
        if let textNode = node as? TextNode {
            return textNode.getWholeText()
        }
        let name = node.nodeName().lowercased()
        let separator = ["br", "p", "div", "li"].contains(name) ? "\n" : ""
        return try node.childNodesCopy().map { try preservedText(in: $0) }.joined() + separator
    }

    private static func isGenius(_ url: URL) -> Bool {
        url.host?.lowercased() == "genius.com" || url.host?.lowercased().hasSuffix(".genius.com") == true
    }

    private static func removingBracketedText(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\n")
    }

    enum ImportError: LocalizedError {
        case emptyQuery
        case lyricsNotFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .emptyQuery: "Enter a song title or artist."
            case .lyricsNotFound: "No lyrics were found on that page."
            case .invalidResponse: "The online source returned an invalid response."
            }
        }
    }

    private static func resultURL(from href: String) -> URL? {
        guard let url = URL(string: href) else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let encoded = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return URL(string: encoded)
        }
        return url.scheme == "https" || url.scheme == "http" ? url : nil
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.invalidResponse
        }
    }
}
