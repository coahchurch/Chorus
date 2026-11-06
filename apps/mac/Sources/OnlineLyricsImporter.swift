import Foundation

struct OnlineLyricsResult: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let snippet: String
}

struct OnlineLyricsContent: Sendable {
    let title: String?
    let lyrics: String
    let transliteration: String
}

enum OnlineLyricsImporter {
    private static let lrclibHost = "lrclib.net"
    private static let tamilChristianWorldHost = "tamilchristianworld.com"
    private static let userAgent = "Chorus/1.0"

    static func search(title: String, artist: String) async throws -> [OnlineLyricsResult] {
        let query = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { throw ImportError.emptyQuery }

        async let lrclibResults = searchLRCLIB(query)
        async let tamilChristianWorldResults = searchTamilChristianWorld(query)
        let (lrclib, tamilChristianWorld) = try await (lrclibResults, tamilChristianWorldResults)
        let prioritizeTamilChristianWorld = containsTamilScript(title)
            || tamilChristianWorld.contains {
                isLikelyTamilTransliteration(title, matching: $0.title)
            }
        let prioritized = prioritizeTamilChristianWorld
            ? tamilChristianWorld + lrclib
            : lrclib + tamilChristianWorld
        return Array(prioritized.prefix(20))
    }

    static func fetchLyrics(from url: URL) async throws -> OnlineLyricsContent {
        guard isLRCLIBAPI(url) || isTamilChristianWorldAPI(url) else {
            throw ImportError.unsupportedSource
        }

        if isLRCLIBAPI(url) {
            let data = try await get(url)
            let song = try JSONDecoder().decode(LRCLIBSong.self, from: data)
            let lyrics = [
                song.plainLyrics,
                song.syncedLyrics.map(plainText(fromSyncedLyrics:))
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            guard let lyrics else {
                throw ImportError.lyricsNotFound
            }
            return OnlineLyricsContent(
                title: song.trackName,
                lyrics: lyrics,
                transliteration: ""
            )
        }

        let data = try await get(url)
        let song = try JSONDecoder().decode(TamilChristianWorldSong.self, from: data)
        let primary = song.sectionText(\.tamilLines, fallback: song.lyrics.tamil)
        let transliteration = song.sectionText(\.englishLines, fallback: song.lyrics.english)
        guard !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.lyricsNotFound
        }
        return OnlineLyricsContent(
            title: song.titleEnglish?.capitalized ?? song.titleTamil,
            lyrics: primary,
            transliteration: transliteration
        )
    }

    private static func searchLRCLIB(_ query: String) async throws -> [OnlineLyricsResult] {
        var components = URLComponents(string: "https://\(lrclibHost)/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let data = try await get(components.url!)
        let songs = try JSONDecoder().decode([LRCLIBSong].self, from: data)
        return songs
            .compactMap { song -> OnlineLyricsResult? in
                guard song.hasLyrics,
                      let url = URL(string: "https://\(lrclibHost)/api/get/\(song.id)")
                else { return nil }
                return OnlineLyricsResult(
                    id: url.absoluteString,
                    title: song.trackName,
                    url: url,
                    snippet: [song.artistName, song.albumName]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
            }
            .prefix(10)
            .map { $0 }
    }

    private static func searchTamilChristianWorld(_ query: String) async throws -> [OnlineLyricsResult] {
        var components = URLComponents(string: "https://\(tamilChristianWorldHost)/api/v1/songs")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(TamilChristianWorldSearchResponse.self, from: data)
        var seen = Set<String>()
        return response.songs
            .compactMap { result -> OnlineLyricsResult? in
                guard let url = URL(string: result.apiURL),
                      isTamilChristianWorldAPI(url),
                      seen.insert(url.absoluteString).inserted
                else { return nil }
                let snippet = [result.artist, result.titleTamil]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                return OnlineLyricsResult(
                    id: url.absoluteString,
                    title: result.displayTitle,
                    url: url,
                    snippet: snippet
                )
            }
            .prefix(10)
            .map { $0 }
    }

    private static func plainText(fromSyncedLyrics text: String) -> String {
        text.components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(
                    of: #"\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func isLRCLIBAPI(_ url: URL) -> Bool {
        hasHost(url, matching: lrclibHost)
            && url.path.hasPrefix("/api/get/")
    }

    private static func containsTamilScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }
    }

    private static func isLikelyTamilTransliteration(_ query: String, matching resultTitle: String) -> Bool {
        let queryWords = Set(searchWords(in: query))
        let resultWords = Set(searchWords(in: resultTitle))
        guard !queryWords.isEmpty else { return false }
        let matchingWordCount = queryWords.intersection(resultWords).count
        if queryWords.count == 1 {
            return matchingWordCount == 1 && queryWords == resultWords
        }
        return Double(matchingWordCount) / Double(queryWords.count) >= 0.6
    }

    private static func searchWords(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func isTamilChristianWorldAPI(_ url: URL) -> Bool {
        hasHost(url, matching: tamilChristianWorldHost)
            && url.path.hasPrefix("/api/v1/songs/")
    }

    private static func hasHost(_ url: URL, matching host: String) -> Bool {
        guard let candidate = url.host?.lowercased() else { return false }
        return candidate == host || candidate.hasSuffix(".\(host)")
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    enum ImportError: LocalizedError {
        case emptyQuery
        case lyricsNotFound
        case invalidResponse
        case unsupportedSource

        var errorDescription: String? {
            switch self {
            case .emptyQuery: "Enter a song title or artist."
            case .lyricsNotFound: "No lyrics were found on that page."
            case .invalidResponse: "An online lyrics source returned an invalid response."
            case .unsupportedSource: "Only LRCLIB and Tamil Christian World API results are supported."
            }
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.invalidResponse
        }
    }
}

private struct LRCLIBSong: Decodable {
    let id: Int
    let trackName: String
    let artistName: String?
    let albumName: String?
    let plainLyrics: String?
    let syncedLyrics: String?

    var hasLyrics: Bool {
        !(plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private struct TamilChristianWorldSearchResponse: Decodable {
    let songs: [Result]

    struct Result: Decodable {
        let titleTamil: String
        let titleEnglish: String
        let artist: String?
        let apiURL: String

        enum CodingKeys: String, CodingKey {
            case titleTamil = "title_ta"
            case titleEnglish = "title_en"
            case artist
            case apiURL = "api_url"
        }

        var displayTitle: String {
            let english = titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? titleTamil : english.capitalized
        }
    }
}

private struct TamilChristianWorldSong: Decodable {
    let titleTamil: String
    let titleEnglish: String?
    let lyrics: Lyrics
    let sections: [Section]?

    struct Lyrics: Decodable {
        let tamil: String?
        let english: String?

        enum CodingKeys: String, CodingKey {
            case tamil = "ta"
            case english = "en"
        }
    }

    struct Section: Decodable {
        let index: Int
        let label: String?
        let tamilLines: [String]
        let englishLines: [String]

        enum CodingKeys: String, CodingKey {
            case index
            case label
            case tamilLines = "ta"
            case englishLines = "en"
        }
    }

    enum CodingKeys: String, CodingKey {
        case titleTamil = "title_ta"
        case titleEnglish = "title_en"
        case lyrics
        case sections
    }

    func sectionText(
        _ lines: KeyPath<Section, [String]>,
        fallback: String?
    ) -> String {
        guard let sections, !sections.isEmpty else { return fallback ?? "" }
        return sections
            .sorted { $0.index < $1.index }
            .map { section in
                let body = section[keyPath: lines].joined(separator: "\n")
                return body
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}
