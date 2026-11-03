import Foundation

public enum OpenLyricsImporter {

    public struct Song: Sendable, Equatable {
        public var title: String?
        public var authors: [String]
        public var publisher: String?
        public var copyright: String?
        public var ccliNumber: Int?
        public var musicKey: String?
        public var lyricsText: String
        public var transliterationText: String?

        public var ccli: CCLIInfo? {
            guard !authors.isEmpty || publisher != nil || copyright != nil || ccliNumber != nil else {
                return nil
            }
            return CCLIInfo(
                songNumber: ccliNumber,
                songTitle: title,
                author: authors.isEmpty ? nil : authors.joined(separator: ", "),
                publisher: publisher,
                copyrightYear: copyright.flatMap {
                    SimpleRegex(#"(\b(?:19|20)\d{2}\b)"#).firstMatch(in: $0).flatMap(Int.init)
                },
                copyright: copyright
            )
        }
    }

    public enum ImportError: Error, LocalizedError, Sendable, Equatable {
        case invalidXML(String)
        case notOpenLyrics
        case noLyrics
        case multipleSongs(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let detail): "OpenLyrics XML could not be read: \(detail)"
            case .notOpenLyrics: "This XML file is not an OpenLyrics song."
            case .noLyrics: "This OpenLyrics song does not contain any lyrics."
            case .multipleSongs(let count): "This OpenLyrics file contains \(count) songs. Import it as a songbook."
            }
        }
    }

    public static func parse(_ data: Data) throws -> Song {
        let songs = try parseSongs(data)
        guard songs.count == 1 else { throw ImportError.multipleSongs(songs.count) }
        return songs[0]
    }

    public static func parseSongs(_ data: Data) throws -> [Song] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw ImportError.invalidXML(parser.parserError?.localizedDescription ?? "Invalid XML.")
        }
        guard reader.isOpenLyrics else { throw ImportError.notOpenLyrics }
        guard !reader.songs.isEmpty else { throw ImportError.noLyrics }
        return reader.songs
    }

    private static func arrangedSections(_ sections: [Reader.Section], verseOrder: String?) -> [Reader.Section] {
        guard let verseOrder else { return sections }
        let byName = Dictionary(grouping: sections, by: { $0.name.lowercased() })
        var used = Set<Int>()
        var arranged: [Reader.Section] = []
        for name in verseOrder.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init) {
            guard let match = byName[name.lowercased()]?.first else { continue }
            used.insert(match.index)
            arranged.append(match)
        }
        arranged.append(contentsOf: sections.filter { !used.contains($0.index) })
        return arranged
    }

    private final class Reader: NSObject, XMLParserDelegate {
        struct Section: Sendable {
            var index: Int
            var name: String
            var label: String
            var lineGroups: [LineGroup]

            var primaryLines: [String] {
                guard let primaryScript else { return [] }
                return lineGroups.filter { $0.script == primaryScript }.flatMap(\.lines)
            }

            var transliterationLines: [String]? {
                guard let primaryScript,
                      let script = lineGroups.first(where: { $0.script == "latin" && $0.script != primaryScript })?.script
                else { return nil }
                return lineGroups.filter { $0.script == script }.flatMap(\.lines)
            }

            private var primaryScript: String? {
                lineGroups.first(where: { $0.script != "latin" })?.script ?? lineGroups.first?.script
            }
        }

        struct LineGroup: Sendable {
            var script: String
            var lines: [String]
        }

        private(set) var isOpenLyrics = false
        private(set) var songs: [Song] = []

        private var titles: [String] = []
        private var authors: [String] = []
        private var publishers: [String] = []
        private var copyrights: [String] = []
        private var ccliNumbers: [String] = []
        private var keys: [String] = []
        private var verseOrder: String?
        private var sections: [Section] = []

        private var stack: [String] = []
        private var inProperties = false
        private var inLyrics = false
        private var inSong = false
        private var propertyName: String?
        private var propertyText = ""
        private var sectionElement: String?
        private var currentSection: Section?
        private var currentLine: String?
        private var currentLineScript = "unknown"
        private var lineElementDepth = 0
        private var hasLineElements = false

        private static let propertyNames: Set<String> = [
            "title", "author", "publisher", "copyright", "cclino", "key", "verseorder",
        ]
        private static let sectionElements: Set<String> = [
            "verse", "chorus", "bridge", "pre-chorus", "prechorus", "tag", "ending",
            "intro", "outro", "interlude", "vamp", "misc",
        ]

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = Self.localName(qName ?? elementName)
            if stack.isEmpty {
                isOpenLyrics = ["song", "songbook", "songbooks"].contains(name)
            }
            if name == "song" {
                inSong = true
                resetSong()
            }

            if inSong, name == "properties" { inProperties = true }
            if inProperties, Self.propertyNames.contains(name) {
                propertyName = name
                propertyText = ""
            }
            if inSong, name == "lyrics" { inLyrics = true }
            if inLyrics, currentSection == nil, Self.sectionElements.contains(name) {
                let partName = Self.attribute("name", in: attributeDict) ?? name
                currentSection = Section(
                    index: sections.count,
                    name: partName,
                    label: Self.sectionLabel(type: name, name: partName),
                    lineGroups: []
                )
                sectionElement = name
            }
            if currentSection != nil, name == "lines", currentLine == nil {
                currentLine = ""
                currentLineScript = Self.attribute("script", in: attributeDict).map(Self.scriptName)
                    ?? Self.attribute("lang", in: attributeDict)?.lowercased()
                    ?? "unknown"
                lineElementDepth = 0
                hasLineElements = false
            } else if currentLine != nil, name == "line" {
                if hasLineElements { currentLine?.append("\n") }
                hasLineElements = true
                lineElementDepth += 1
            } else if currentLine != nil, name == "chord",
                      let chord = Self.attribute("name", in: attributeDict), !chord.isEmpty {
                currentLine?.append("[\(chord)]")
            } else if currentLine != nil, name == "br" {
                currentLine?.append("\n")
            }
            stack.append(name)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if propertyName != nil {
                propertyText.append(string)
            } else if currentLine != nil {
                currentLine?.append(string)
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = Self.localName(qName ?? elementName)
            if name == propertyName {
                let value = propertyText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    switch name {
                    case "title": titles.append(value)
                    case "author": authors.append(value)
                    case "publisher": publishers.append(value)
                    case "copyright": copyrights.append(value)
                    case "cclino": ccliNumbers.append(value)
                    case "key": keys.append(value)
                    case "verseorder": verseOrder = value
                    default: break
                    }
                }
                propertyName = nil
                propertyText = ""
            }
            if name == "line", lineElementDepth > 0 {
                lineElementDepth -= 1
            }
            if name == "lines", let line = currentLine {
                let lines = line.components(separatedBy: "\n").compactMap {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                if !lines.isEmpty {
                    currentSection?.lineGroups.append(LineGroup(script: currentLineScript, lines: lines))
                }
                currentLine = nil
                currentLineScript = "unknown"
                lineElementDepth = 0
                hasLineElements = false
            }
            if name == sectionElement, let section = currentSection {
                if !section.primaryLines.isEmpty {
                    sections.append(section)
                }
                currentSection = nil
                sectionElement = nil
            }
            if name == "lyrics" { inLyrics = false }
            if name == "properties" { inProperties = false }
            if name == "song", inSong {
                appendSong()
                inSong = false
            }
            if !stack.isEmpty { stack.removeLast() }
        }

        private func resetSong() {
            titles = []
            authors = []
            publishers = []
            copyrights = []
            ccliNumbers = []
            keys = []
            verseOrder = nil
            sections = []
            inProperties = false
            inLyrics = false
            propertyName = nil
            propertyText = ""
            sectionElement = nil
            currentSection = nil
            currentLine = nil
            currentLineScript = "unknown"
            lineElementDepth = 0
            hasLineElements = false
        }

        private func appendSong() {
            guard !sections.isEmpty else { return }
            let arranged = OpenLyricsImporter.arrangedSections(sections, verseOrder: verseOrder)
            let lyrics = arranged
                .map { section in
                    "{c: \(section.label)}\n" + section.primaryLines.joined(separator: "\n")
                }
                .joined(separator: "\n\n")
            let hasTransliteration = arranged.contains { $0.transliterationLines != nil }
            let transliteration = hasTransliteration
                ? arranged.map { section in
                    "{c: \(section.label)}\n" + (section.transliterationLines ?? []).joined(separator: "\n")
                }.joined(separator: "\n\n")
                : nil
            songs.append(Song(
                title: titles.first,
                authors: authors,
                publisher: publishers.first,
                copyright: copyrights.first,
                ccliNumber: ccliNumbers.first.flatMap { Int($0.filter(\.isNumber)) },
                musicKey: keys.first.flatMap { ChordMath.parseKey($0) == nil ? nil : $0 },
                lyricsText: lyrics,
                transliterationText: transliteration
            ))
        }

        private static func localName(_ name: String) -> String {
            String(name.split(separator: ":").last ?? Substring(name)).lowercased()
        }

        private static func attribute(_ name: String, in attributes: [String: String]) -> String? {
            attributes.first { localName($0.key) == name }?.value
        }

        private static func scriptName(_ value: String) -> String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["latin", "latn"].contains(normalized) ? "latin" : normalized
        }

        private static func sectionLabel(type: String, name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            let codes: [(String, String)] = [
                ("pre-chorus", "Pre-Chorus"), ("prechorus", "Pre-Chorus"),
                ("verse", "Verse"), ("chorus", "Chorus"), ("bridge", "Bridge"),
                ("interlude", "Interlude"), ("ending", "Ending"), ("intro", "Intro"),
                ("outro", "Outro"), ("vamp", "Vamp"), ("tag", "Tag"), ("misc", "Part"),
                ("v", "Verse"), ("c", "Chorus"), ("b", "Bridge"), ("p", "Pre-Chorus"),
                ("i", "Intro"), ("e", "Ending"), ("o", "Outro"), ("t", "Tag"),
            ]
            for (code, label) in codes where lower.hasPrefix(code) {
                let suffix = String(lower.dropFirst(code.count))
                if suffix.isEmpty { return label }
                if suffix.first?.isNumber == true || code.count > 1 {
                    return "\(label) \(suffix)"
                }
            }
            let typeLabel = codes.first(where: { $0.0 == type })?.1 ?? type.capitalized
            return trimmed.isEmpty || trimmed == type ? typeLabel : "\(typeLabel) \(trimmed)"
        }
    }
}
