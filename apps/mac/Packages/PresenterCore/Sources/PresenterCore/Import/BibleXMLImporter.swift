import Foundation

public enum BibleXMLImporter {
    public static let parsedVerseServiceMarker = "chorus.parsedBibleVerse"
    public static let parsedPassageServiceMarker = "chorus.parsedBiblePassage"

    public struct Verse: Codable, Equatable, Sendable, Identifiable {
        public var book: String
        public var bookNumber: Int?
        public var chapter: Int
        public var number: Int
        public var text: String

        public var id: String { "\(book)|\(chapter)|\(number)" }
    }

    public struct Version: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var sourceName: String
        public var importedAt: Date
        public var copyright: String?
        public var verses: [Verse]

        public init(
            id: String = UUID().uuidString, name: String, sourceName: String,
            importedAt: Date = .now, copyright: String? = nil, verses: [Verse]
        ) {
            self.id = id
            self.name = name
            self.sourceName = sourceName
            self.importedAt = importedAt
            self.copyright = copyright
            self.verses = verses
        }

        public var books: [String] {
            var bookNumbers: [String: Int] = [:]
            for verse in verses where bookNumbers[verse.book] == nil {
                bookNumbers[verse.book] = verse.bookNumber
                    ?? BibleXMLImporter.bookNames.firstIndex(of: verse.book).map { $0 + 1 }
                    ?? Int.max
            }
            return bookNumbers.keys.sorted { firstName, secondName in
                let firstNumber = bookNumbers[firstName] ?? Int.max
                let secondNumber = bookNumbers[secondName] ?? Int.max
                return firstNumber == secondNumber
                    ? firstName.localizedStandardCompare(secondName) == .orderedAscending
                    : firstNumber < secondNumber
            }
        }
    }

    public struct SearchHit: Equatable, Sendable, Identifiable {
        public var versionID: String
        public var versionName: String
        public var verse: Verse

        public var id: String { "\(versionID)|\(verse.id)" }

        public init(versionID: String, versionName: String, verse: Verse) {
            self.versionID = versionID
            self.versionName = versionName
            self.verse = verse
        }
    }

    public struct Reference: Equatable, Sendable {
        public var book: String
        public var chapter: Int
        public var verses: ClosedRange<Int>?
        public var endChapter: Int?
        public var endVerse: Int?

        public init(
            book: String, chapter: Int, verses: ClosedRange<Int>? = nil,
            endChapter: Int? = nil, endVerse: Int? = nil
        ) {
            self.book = book
            self.chapter = chapter
            self.verses = verses
            self.endChapter = endChapter
            self.endVerse = endVerse
        }

        public var displayName: String {
            if let verses {
                let start = "\(book) \(chapter):\(verses.lowerBound)"
                if let endChapter {
                    return "\(start)–\(endChapter):\(endVerse ?? verses.upperBound)"
                }
                return verses.lowerBound == verses.upperBound
                    ? start : "\(start)–\(verses.upperBound)"
            }
            if let endChapter {
                return "\(book) \(chapter)–\(endChapter)"
            }
            return "\(book) \(chapter)"
        }
    }

    public enum ImportError: Error, LocalizedError, Sendable, Equatable {
        case invalidXML(String)
        case noVerses

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let detail): "Bible XML could not be read: \(detail)"
            case .noVerses: "This XML contains no recognizable Bible verses."
            }
        }
    }

    public static func parse(_ data: Data, versionName: String, sourceName: String) throws -> Version {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw ImportError.invalidXML(parser.parserError?.localizedDescription ?? "Invalid XML.")
        }
        guard !reader.verses.isEmpty else { throw ImportError.noVerses }
        return Version(name: versionName, sourceName: sourceName, verses: reader.verses)
    }

    public static func search(
        versions: [Version], query: String, limit: Int = 200
    ) -> [SearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }

        if let reference = reference(from: query) {
            return versions.flatMap { version in
                version.verses.lazy
                    .filter { verse in
                        verse.book == reference.book && verse.chapter == reference.chapter
                            && (reference.verses.map { $0.contains(verse.number) } ?? true)
                    }
                    .prefix(limit)
                    .map {
                        SearchHit(versionID: version.id, versionName: version.name, verse: $0)
                    }
            }.prefix(limit).map { $0 }
        }

        let normalizedQuery = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        )
        var matches: [SearchHit] = []
        for version in versions {
            for verse in version.verses {
                let normalizedText = verse.text.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                guard normalizedText.contains(normalizedQuery) else { continue }
                matches.append(SearchHit(
                    versionID: version.id, versionName: version.name, verse: verse
                ))
                if matches.count == limit { return matches }
            }
        }
        return matches
    }

    public static func reference(from query: String) -> Reference? {
        let pattern = #"^\s*(.+?)\s+(\d+)(?::(\d+)(?:\s*[-–]\s*(\d+))?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: query, range: NSRange(query.startIndex..., in: query)
              ),
              let bookRange = Range(match.range(at: 1), in: query),
              let chapterRange = Range(match.range(at: 2), in: query),
              let chapter = Int(query[chapterRange])
        else { return nil }
        let book = canonicalBookName(String(query[bookRange]))
        guard bookNames.contains(book), chapter > 0 else { return nil }
        let verseStart = Range(match.range(at: 3), in: query).flatMap {
            Int(query[$0])
        }
        let verseEnd = Range(match.range(at: 4), in: query).flatMap {
            Int(query[$0])
        } ?? verseStart
        guard let verseStart else {
            return Reference(book: book, chapter: chapter, verses: nil)
        }
        guard let verseEnd, verseEnd >= verseStart else { return nil }
        return Reference(book: book, chapter: chapter, verses: verseStart...verseEnd)
    }

    public static func references(in text: String) -> [Reference] {
        let aliases = bookAliases.keys.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }
        let bookPattern = aliases.map { alias in
            alias.split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
        }.joined(separator: "|")
        let pattern = #"(?<![\p{L}\p{N}])(?<book>\#(bookPattern))(?![\p{L}\p{N}])\.?\s+(?<chapter>\d+)(?:\s*:\s*(?<verse>\d+)(?:\s*[-–—]\s*(?:(?<endChapter>\d+)\s*:\s*)?(?<endVerse>\d+))?|\s*[-–—]\s*(?<endChapterOnly>\d+))?"#
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Bible reference pattern is invalid: \(error)")
        }
        let shorthandRegex: NSRegularExpression
        do {
            shorthandRegex = try NSRegularExpression(
                pattern: #"^\s*,\s*(\d+)(?:\s*[-–—]\s*(\d+))?"#
            )
        } catch {
            preconditionFailure("Bible shorthand reference pattern is invalid: \(error)")
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var references: [Reference] = []
        var consumedUntil = 0
        for match in matches where match.range.location >= consumedUntil {
            guard let reference = reference(from: text, match: match) else { continue }
            references.append(reference)
            consumedUntil = NSMaxRange(match.range)

            guard reference.endChapter == nil, reference.verses != nil else {
                continue
            }
            while consumedUntil < nsText.length {
                let remainingRange = NSRange(
                    location: consumedUntil, length: nsText.length - consumedUntil
                )
                guard let remainingTextRange = Range(remainingRange, in: text) else { break }
                let remainingText = String(text[remainingTextRange])
                let remainingNSString = remainingText as NSString
                guard let shorthand = shorthandRegex.firstMatch(
                    in: remainingText,
                    range: NSRange(location: 0, length: remainingNSString.length)
                ), let startRange = Range(shorthand.range(at: 1), in: remainingText),
                   let startVerse = Int(remainingText[startRange]) else {
                    break
                }
                let endVerse = Range(shorthand.range(at: 2), in: remainingText)
                    .flatMap { Int(remainingText[$0]) } ?? startVerse
                guard endVerse >= startVerse else { break }
                references.append(Reference(
                    book: reference.book,
                    chapter: reference.chapter,
                    verses: startVerse...endVerse
                ))
                consumedUntil += NSMaxRange(shorthand.range)
            }
        }
        return references
    }

    private static func reference(
        from text: String, match: NSTextCheckingResult
    ) -> Reference? {
        guard let bookRange = Range(match.range(withName: "book"), in: text),
              let chapterRange = Range(match.range(withName: "chapter"), in: text),
              let chapter = Int(text[chapterRange]), chapter > 0 else {
            return nil
        }
        let book = canonicalBookName(String(text[bookRange]))
        guard bookNames.contains(book) else { return nil }

        let verse = Range(match.range(withName: "verse"), in: text)
            .flatMap { Int(text[$0]) }
        let endVerse = Range(match.range(withName: "endVerse"), in: text)
            .flatMap { Int(text[$0]) }
        let endChapter = Range(match.range(withName: "endChapter"), in: text)
            .flatMap { Int(text[$0]) }
        let endChapterOnly = Range(match.range(withName: "endChapterOnly"), in: text)
            .flatMap { Int(text[$0]) }

        if let endChapterOnly {
            guard endChapterOnly >= chapter else { return nil }
            return Reference(book: book, chapter: chapter, endChapter: endChapterOnly)
        }
        guard let verse else {
            return Reference(book: book, chapter: chapter)
        }
        let finalChapter = endChapter ?? chapter
        let finalVerse = endVerse ?? verse
        guard finalChapter >= chapter,
              finalChapter != chapter || finalVerse >= verse,
              finalVerse > 0 else {
            return nil
        }
        let verseRange = endChapter == nil ? verse...(endVerse ?? verse) : verse...verse
        return Reference(
            book: book, chapter: chapter, verses: verseRange,
            endChapter: endChapter, endVerse: endChapter == nil ? nil : endVerse
        )
    }

    public static func verses(
        for reference: Reference, in version: Version
    ) -> [Verse]? {
        let lastChapter = reference.endChapter ?? reference.chapter
        let matches = version.verses
            .filter { verse in
                guard verse.book == reference.book,
                      (reference.chapter...lastChapter).contains(verse.chapter) else {
                    return false
                }
                if verse.chapter == reference.chapter,
                   let startVerse = reference.verses?.lowerBound,
                   verse.number < startVerse {
                    return false
                }
                if verse.chapter == reference.chapter,
                   reference.endChapter == nil,
                   let endVerse = reference.verses?.upperBound,
                   verse.number > endVerse {
                    return false
                }
                if verse.chapter == lastChapter,
                   let endVerse = reference.endVerse,
                   verse.number > endVerse {
                    return false
                }
                return true
            }
            .sorted {
                ($0.chapter, $0.number) < ($1.chapter, $1.number)
            }

        guard !matches.isEmpty,
              matches.first?.chapter == reference.chapter else {
            return nil
        }
        let availableChapters = Set(matches.map(\.chapter))
        guard (reference.chapter...lastChapter).allSatisfy(availableChapters.contains) else {
            return nil
        }
        if let startVerse = reference.verses?.lowerBound {
            guard matches.first?.chapter == reference.chapter,
                  matches.first?.number == startVerse else {
                return nil
            }
        }
        if let endVerse = reference.endVerse {
            guard matches.last?.chapter == lastChapter,
                  matches.last?.number == endVerse else {
                return nil
            }
        } else if reference.endChapter == nil,
                  let endVerse = reference.verses?.upperBound,
                  matches.last?.chapter != reference.chapter || matches.last?.number != endVerse {
            return nil
        } else if reference.endChapter != nil,
                  matches.last?.chapter != lastChapter {
            return nil
        }
        return matches
    }

    public static func canonicalBookName(_ rawValue: String, bookNumber: Int? = nil) -> String {
        if let bookNumber, (1...bookNames.count).contains(bookNumber) {
            return bookNames[bookNumber - 1]
        }
        let normalized = rawValue
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
            .lowercased()
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        return bookAliases[normalized] ?? bookAliases[compact]
            ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let bookNames = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
        "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra",
        "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon",
        "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
        "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah",
        "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
        "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians",
        "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James",
        "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
    ]

    private static let bookAliases: [String: String] = {
        var aliases: [String: String] = [:]
        let forms: [(String, [String])] = [
            ("Genesis", ["gen", "gn"]), ("Exodus", ["exod", "ex"]), ("Leviticus", ["lev"]),
            ("Numbers", ["num", "nm"]), ("Deuteronomy", ["deut", "dt"]), ("Joshua", ["josh"]),
            ("Judges", ["judg"]), ("Ruth", []), ("1 Samuel", ["1 samuel", "i samuel", "1 sam", "1sa"]),
            ("2 Samuel", ["2 samuel", "ii samuel", "2 sam", "2sa"]), ("1 Kings", ["1 kgs", "i kings"]),
            ("2 Kings", ["2 kgs", "ii kings"]), ("1 Chronicles", ["1 chron", "i chronicles"]),
            ("2 Chronicles", ["2 chron", "ii chronicles"]), ("Ezra", []), ("Nehemiah", ["neh"]),
            ("Esther", ["esth"]), ("Job", []), ("Psalms", ["psalm", "ps", "pss"]),
            ("Proverbs", ["prov"]), ("Ecclesiastes", ["eccl"]), ("Song of Solomon", ["song of songs", "song"]),
            ("Isaiah", ["isa"]), ("Jeremiah", ["jer"]), ("Lamentations", ["lam"]),
            ("Ezekiel", ["ezek"]), ("Daniel", ["dan"]), ("Hosea", ["hos"]), ("Joel", []),
            ("Amos", []), ("Obadiah", ["obad"]), ("Jonah", ["jon"]), ("Micah", ["mic"]),
            ("Nahum", ["nah"]), ("Habakkuk", ["hab"]), ("Zephaniah", ["zeph"]), ("Haggai", ["hag"]),
            ("Zechariah", ["zech"]), ("Malachi", ["mal"]), ("Matthew", ["matt", "mt"]),
            ("Mark", ["mk"]), ("Luke", ["lk"]), ("John", ["jn"]), ("Acts", []),
            ("Romans", ["rom"]), ("1 Corinthians", ["1 cor", "i corinthians"]),
            ("2 Corinthians", ["2 cor", "ii corinthians"]), ("Galatians", ["gal"]),
            ("Ephesians", ["eph"]), ("Philippians", ["phil"]), ("Colossians", ["col"]),
            ("1 Thessalonians", ["1 thess", "i thessalonians"]),
            ("2 Thessalonians", ["2 thess", "ii thessalonians"]),
            ("1 Timothy", ["1 tim", "i timothy"]), ("2 Timothy", ["2 tim", "ii timothy"]),
            ("Titus", []), ("Philemon", ["phlm"]), ("Hebrews", ["heb"]), ("James", ["jas"]),
            ("1 Peter", ["1 pet", "i peter"]), ("2 Peter", ["2 pet", "ii peter"]),
            ("1 John", ["1 jn", "i john"]), ("2 John", ["2 jn", "ii john"]),
            ("3 John", ["3 jn", "iii john"]), ("Jude", []), ("Revelation", ["rev"]),
        ]
        for (name, shortNames) in forms {
            aliases[name.lowercased()] = name
            aliases[name.replacingOccurrences(of: " ", with: "").lowercased()] = name
            for shortName in shortNames {
                aliases[shortName.lowercased()] = name
                aliases[shortName.replacingOccurrences(of: " ", with: "").lowercased()] = name
            }
        }
        for (index, name) in bookNames.enumerated() {
            aliases[String(index + 1)] = name
        }
        return aliases
    }()

    private final class Reader: NSObject, XMLParserDelegate {
        private(set) var verses: [Verse] = []
        private var bookName = ""
        private var bookNumber: Int?
        private var chapter = 0
        private var verseNumber: Int?
        private var verseText = ""
        private var ignoredDepth = 0
        private var closingMilestoneStart = false

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let element = Self.localName(qName ?? elementName)
            let attributes = Dictionary(
                attributeDict.map { (Self.localName($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            switch element {
            case "book", "biblebook":
                let rawBook = attributes["bname"] ?? attributes["name"]
                    ?? attributes["osisid"] ?? attributes["id"] ?? ""
                let rawNumber = attributes["bnumber"] ?? attributes["number"]
                bookNumber = rawNumber.flatMap(Int.init)
                bookName = BibleXMLImporter.canonicalBookName(rawBook, bookNumber: bookNumber)
            case "div" where attributes["type"]?.lowercased() == "book":
                let rawBook = attributes["osisid"] ?? attributes["name"] ?? ""
                bookName = BibleXMLImporter.canonicalBookName(rawBook)
            case "chapter":
                let rawID = attributes["osisid"] ?? attributes["cnumber"]
                    ?? attributes["number"] ?? attributes["id"] ?? ""
                chapter = Self.trailingNumber(rawID) ?? Int(rawID) ?? 0
            case "vers", "verse":
                let rawNumber = attributes["vnumber"] ?? attributes["number"]
                    ?? attributes["osisid"] ?? attributes["sid"] ?? attributes["id"] ?? ""
                if attributes["eid"] != nil {
                    finishVerse()
                    closingMilestoneStart = true
                    return
                }
                let parsed = Self.verseIdentity(rawNumber)
                if let parsedChapter = parsed.chapter { chapter = parsedChapter }
                verseNumber = parsed.verse
                verseText = ""
                closingMilestoneStart = attributes["sid"] != nil
            case "note", "footnote", "crossreference", "crossref":
                ignoredDepth += 1
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard verseNumber != nil, ignoredDepth == 0 else { return }
            verseText.append(string)
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName qName: String?
        ) {
            switch Self.localName(qName ?? elementName) {
            case "vers", "verse":
                if closingMilestoneStart {
                    closingMilestoneStart = false
                } else {
                    finishVerse()
                }
            case "note", "footnote", "crossreference", "crossref":
                ignoredDepth = max(0, ignoredDepth - 1)
            default:
                break
            }
        }

        private func finishVerse() {
            guard let verseNumber, chapter > 0, !bookName.isEmpty else { return }
            let text = verseText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                verses.append(Verse(
                    book: bookName, bookNumber: bookNumber,
                    chapter: chapter, number: verseNumber, text: text
                ))
            }
            self.verseNumber = nil
            verseText = ""
        }

        private static func verseIdentity(_ rawValue: String) -> (chapter: Int?, verse: Int?) {
            let components = rawValue.split(separator: ".").compactMap { Int($0) }
            if components.count >= 3 { return (components[components.count - 2], components.last) }
            if components.count == 2, rawValue.contains(".") { return (components[0], components[1]) }
            return (nil, components.last)
        }

        private static func trailingNumber(_ rawValue: String) -> Int? {
            rawValue.split(separator: ".").last.flatMap { Int($0) }
                ?? rawValue.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
        }

        private static func localName(_ name: String) -> String {
            String(name.split(separator: ":").last ?? Substring(name)).lowercased()
        }
    }
}
