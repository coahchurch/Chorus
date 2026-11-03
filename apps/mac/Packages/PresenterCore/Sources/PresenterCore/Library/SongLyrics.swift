import Foundation

public struct SongLyricsPart: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var primaryLines: [String]
    public var transliterationLines: [String]

    public init(
        id: String = UUID().uuidString,
        label: String,
        primaryLines: [String] = [],
        transliterationLines: [String] = []
    ) {
        self.id = id
        self.label = label
        self.primaryLines = Self.cleaned(primaryLines)
        self.transliterationLines = Self.cleaned(transliterationLines)
    }

    private static func cleaned(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct SongLyrics: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String?
    public var copyright: String?
    public var primaryLanguage: String?
    public var key: String?
    public var tempo: Double?
    public var ccliNumber: Int?
    public var parts: [SongLyricsPart]
    public var folder: String?
    public var folderId: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        author: String? = nil,
        copyright: String? = nil,
        primaryLanguage: String? = nil,
        key: String? = nil,
        tempo: Double? = nil,
        ccliNumber: Int? = nil,
        parts: [SongLyricsPart],
        folder: String? = nil,
        folderId: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = author
        self.copyright = copyright
        self.primaryLanguage = primaryLanguage
        self.key = key
        self.tempo = tempo
        self.ccliNumber = ccliNumber
        self.parts = parts
        self.folder = folder
        self.folderId = folderId
    }

    public var primaryText: String {
        parts.map { part in
            "{c: \(part.label)}\n" + part.primaryLines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    public var transliterationText: String? {
        guard parts.contains(where: { !$0.transliterationLines.isEmpty }) else { return nil }
        return parts.map { part in
            "{c: \(part.label)}\n" + part.transliterationLines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    public func presentation(
        linesPerSlide: Int = 2,
        themeId: String = "",
        themeSlideName: String = "Lyrics"
    ) -> Presentation {
        let ccli = CCLIInfo(
            songNumber: ccliNumber,
            songTitle: name,
            author: author,
            publisher: nil,
            copyrightYear: copyright.flatMap {
                SimpleRegex(#"(\b(?:19|20)\d{2}\b)"#).firstMatch(in: $0).flatMap(Int.init)
            },
            copyright: copyright
        )
        var result = LyricTextImporter.makePresentation(
            primaryText,
            fallbackTitle: name,
            id: "song-lyrics:\(id)",
            themeId: themeId,
            themeSlideName: themeSlideName,
            linesPerSlide: linesPerSlide,
            transliteration: transliterationText,
            phraseAware: false
        )
        result.name = name
        result.presentationKind = .song
        result.arrangements = nil
        result.defaultArrangementId = nil
        result.ccli = ccli
        result.musicKey = key
        result.origin = PresentationOrigin(.madeHere, detail: "Song lyrics")
        for slideIndex in result.slides.indices {
            let slideID = "\(result.id)|slide|\(slideIndex)"
            result.slides[slideIndex].id = slideID
            for objectIndex in result.slides[slideIndex].objects.indices {
                result.slides[slideIndex].objects[objectIndex].id =
                    "\(slideID)|object|\(objectIndex)"
            }
        }
        return result
    }

    public var indexText: String {
        (parts.flatMap(\.primaryLines) + parts.flatMap(\.transliterationLines))
            .joined(separator: " ")
    }
}

extension SongLyrics: DocumentEntity {
    public static var documentKind: DocumentKind { .song }

    public var indexCCLI: IndexCCLI {
        IndexCCLI(number: ccliNumber, title: name)
    }
}

extension SongLyrics: TeamFolderedEntity {}

public extension SongLyrics {
    static func openLyrics(
        _ source: OpenLyricsImporter.Song, includeTransliteration: Bool = true
    ) -> SongLyrics {
        let primary = parseParts(source.lyricsText)
        let transliteration = parseParts(includeTransliteration ? source.transliterationText ?? "" : "")
        let parts = primary.enumerated().map { index, part in
            SongLyricsPart(
                label: part.label,
                primaryLines: part.lines,
                transliterationLines: transliteration.indices.contains(index)
                    ? transliteration[index].lines : []
            )
        }
        return SongLyrics(
            name: source.title ?? "Untitled Song",
            author: source.authors.isEmpty ? nil : source.authors.joined(separator: ", "),
            copyright: source.copyright,
            key: source.musicKey,
            ccliNumber: source.ccliNumber,
            parts: parts
        )
    }

    static func pasted(
        name: String,
        primaryText: String,
        transliterationText: String = ""
    ) -> SongLyrics {
        let primaryParts = parseParts(primaryText)
        let transliterationParts = parseParts(transliterationText)
        let parts = primaryParts.enumerated().map { index, part in
            SongLyricsPart(
                label: part.label,
                primaryLines: part.lines,
                transliterationLines: transliterationParts.indices.contains(index)
                    ? transliterationParts[index].lines : []
            )
        }
        return SongLyrics(name: name, parts: parts)
    }

    private static func parseParts(_ text: String) -> [(label: String, lines: [String])] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var parts: [(label: String, lines: [String])] = []
        var label: String?
        var lines: [String] = []

        func flush() {
            guard !lines.isEmpty else { return }
            parts.append((label ?? "Verse \(parts.count + 1)", lines))
            label = nil
            lines = []
        }

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
            } else if let parsed = partLabel(of: line) {
                flush()
                label = parsed
            } else {
                if label == nil { label = "Verse \(parts.count + 1)" }
                lines.append(line)
            }
        }
        flush()
        return parts
    }

    private static func partLabel(of line: String) -> String? {
        if let label = Reflow.labelName(of: line) { return label }
        guard line.hasPrefix("{"), line.hasSuffix("}") else { return nil }
        let directive = String(line.dropFirst().dropLast())
        let fields = directive.split(separator: ":", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let key = fields[0].lowercased()
        let value = fields.count > 1 ? fields[1] : ""
        switch key {
        case "c", "comment":
            return Reflow.labelName(of: value) ?? (value.isEmpty ? nil : value)
        case "start_of_verse", "sov": return value.isEmpty ? "Verse" : value
        case "start_of_chorus", "soc": return value.isEmpty ? "Chorus" : value
        case "start_of_bridge", "sob": return value.isEmpty ? "Bridge" : value
        case "start_of_part": return value.isEmpty ? nil : value
        default: return nil
        }
    }
}
