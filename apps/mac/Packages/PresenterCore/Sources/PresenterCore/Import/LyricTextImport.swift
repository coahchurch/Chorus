import Foundation

public enum LyricTextFormat: String, Sendable, Equatable {
    case songSelect
    case chordPro

    case chordChart
    case plainText
}

public enum LyricTextImporter {

    public struct Normalized: Equatable {
        public var format: LyricTextFormat
        public var title: String?
        public var ccli: CCLIInfo?
        public var chordProSource: String?

        public var musicKey: String?

        public var body: String

        public var extraLabels: [String] = []
    }

    public static func chordChartLines(_ text: String) -> [String] {
        ChordChartText.chordLines(in: unified(text))
    }

    static func unified(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public static func detectFormat(_ text: String, lyricLines: Set<String> = []) -> LyricTextFormat {
        if ccliSongNumberRegex.firstMatch(in: text) != nil { return .songSelect }
        var directiveHits = 0
        var chordLineHits = 0
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if chordProDirectiveRegex.wholeMatch(trimmed) { directiveHits += 1 }
            if inlineChordRegex.firstMatch(in: trimmed) != nil { chordLineHits += 1 }
        }
        if directiveHits >= 1 {
            return .chordPro
        } else if ChordChartText.inlined(unified(text), lyricLines: lyricLines).chordCount >= 2 {
            return .chordChart
        } else if chordLineHits >= 2 {
            return .chordPro
        } else {
            return .plainText
        }
    }

    public static func makePresentation(
        _ text: String,
        fallbackTitle: String? = nil,
        id: String = UUID().uuidString,
        folder: String? = nil,
        themeId: String = "",
        themeSlideName: String = "Lyrics",
        linesPerSlide: Int = 2,
        lyricLines: Set<String> = [],
        secondaryLyrics: String? = nil,
        transliteration: String? = nil,
        phraseAware: Bool? = nil
    ) -> Presentation {
        var normalized = normalize(text, lyricLines: lyricLines)
        let additionalLines = [
            secondaryLyrics.map { normalize($0).body },
            transliteration.map { normalize($0).body },
        ].compactMap { value in
            value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        let displayLineCount = 1 + additionalLines.count
        if !additionalLines.isEmpty {
            normalized.body = pairedLyrics(primary: normalized.body, additional: additionalLines)
        }

        let groupedBody = groupedPairedLyrics(normalized.body, linesPerSlide: linesPerSlide)
        let phrased = phraseAware ?? (normalized.format != .plainText)
        let built = Reflow.build(
            Reflow.parse(
                groupedBody, linesPerSlide: linesPerSlide * displayLineCount, extraLabels: normalized.extraLabels,
                phrased: phrased
            )
                .openingOnBlank(),
            themeSlideName: themeSlideName
        )
        var slides = built.slides
        if slides.isEmpty {
            slides = [Slide(id: UUID().uuidString, name: "", objects: [])]
        }
        var presentation = Presentation(
            id: id,
            name: normalized.title ?? fallbackTitle ?? "Imported Lyrics",
            presentationKind: .deck,
            themeId: themeId,
            folder: folder,
            slides: slides,
            sections: built.sections.isEmpty ? nil : built.sections,
            arrangements: built.arrangement.map { [$0] },
            defaultArrangementId: built.arrangement?.id,
            reflowSource: normalized.body.isEmpty ? nil : normalized.body,
            ccli: normalized.ccli,
            chordProSource: normalized.chordProSource,
            musicKey: normalized.musicKey
        )
        if phrased {

            presentation.reflowSource = ChordProExport.reflowSeed(for: presentation)
        }
        return presentation
    }

    public static func lyricLineCount(_ text: String) -> Int {
        normalize(text).body.components(separatedBy: .newlines).filter { line in
            !line.trimmingCharacters(in: .whitespaces).isEmpty
                && Reflow.labelName(of: line) == nil
        }.count
    }

    public static func reflowPresentation(
        _ presentation: Presentation, linesPerSlide: Int
    ) -> Presentation? {
        let source = ChordProExport.reflowSeed(for: presentation)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let multiplier = hasPairedScripts(source) ? 2 : 1
        let groupedSource = groupedPairedLyrics(source, linesPerSlide: linesPerSlide)
        let built = Reflow.build(
            from: groupedSource,
            linesPerSlide: max(1, linesPerSlide) * multiplier,
            themeSlideName: Reflow.lyricDesign(of: presentation.slides)
        )
        guard !built.slides.isEmpty else { return nil }

        var result = presentation
        let originalSections = presentation.sections ?? []
        let originalsByName = Dictionary(
            grouping: originalSections, by: { $0.name }
        )
        var rebuiltSections = built.sections
        var remappedSectionIDs: [String: String] = [:]
        for index in rebuiltSections.indices {
            let section = rebuiltSections[index]
            guard let original = originalsByName[section.name]?.first else { continue }
            remappedSectionIDs[section.id] = original.id
            rebuiltSections[index] = PresentationSection(
                id: original.id, name: section.name,
                background: original.background, colorHex: original.colorHex
            )
        }
        let rebuiltNames = Set(rebuiltSections.map(\.name))
        rebuiltSections.append(contentsOf: originalSections.filter { !rebuiltNames.contains($0.name) })

        result.slides = built.slides.map { slide in
            var slide = slide
            if let sectionID = slide.sectionId, let originalID = remappedSectionIDs[sectionID] {
                slide.sectionId = originalID
            }
            return slide
        }
        result.sections = rebuiltSections
        if let arrangements = presentation.arrangements {
            result.arrangements = arrangements
            result.defaultArrangementId = presentation.defaultArrangementId
        } else if var arrangement = built.arrangement {
            arrangement.sectionIds = arrangement.sectionIds.map { remappedSectionIDs[$0] ?? $0 }
            result.arrangements = [arrangement]
            result.defaultArrangementId = arrangement.id
        } else {
            result.arrangements = nil
            result.defaultArrangementId = nil
        }
        result.reflowSource = source
        return result
    }

    public static func displayedLyricLinesPerSlide(in presentation: Presentation) -> Int {
        let source = ChordProExport.reflowSeed(for: presentation)
        let multiplier = hasPairedScripts(source) ? 2 : 1
        let largestSlide = presentation.slides.map { slide in
            slide.objects.reduce(0) { count, object in
                count + object.text.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            }
        }.max() ?? 1
        return max(1, largestSlide / multiplier)
    }

    static func groupedPairedLyrics(_ text: String, linesPerSlide: Int) -> String {
        var result: [String] = []
        var run: [String] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            var groups: [[String]] = []
            var index = 0
            while index < run.count {
                guard scriptClass(of: run[index]) != true else {
                    groups.removeAll()
                    break
                }
                var group = [run[index]]
                index += 1
                while index < run.count, group.count < 3,
                      scriptClass(of: run[index]) == true {
                    group.append(run[index])
                    index += 1
                }
                groups.append(group)
            }

            guard !groups.isEmpty else {
                result.append(contentsOf: run)
                run.removeAll(keepingCapacity: true)
                return
            }

            let primaryLinesPerSlide = max(1, linesPerSlide)
            for start in stride(from: 0, to: groups.count, by: primaryLinesPerSlide) {
                let chunk = groups[start..<min(start + primaryLinesPerSlide, groups.count)]
                result.append(contentsOf: chunk.map { $0[0] })
                for languageIndex in 1..<3 {
                    result.append(contentsOf: chunk.compactMap {
                        $0.indices.contains(languageIndex) ? $0[languageIndex] : nil
                    })
                }
            }
            run.removeAll(keepingCapacity: true)
        }

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || Reflow.labelName(of: line) != nil {
                flushRun()
                result.append(line)
            } else {
                run.append(line)
            }
        }
        flushRun()
        return result.joined(separator: "\n")
    }

    static func samePairedScriptLines(_ first: [String], _ second: [String]) -> Bool {
        func streams(_ lines: [String]) -> (labels: [String], primary: [String], latin: [String])? {
            var labels: [String] = []
            var primary: [String] = []
            var latin: [String] = []
            for line in lines {
                if Reflow.labelName(of: line) != nil {
                    labels.append(line)
                } else if scriptClass(of: line) == true {
                    latin.append(line)
                } else if scriptClass(of: line) == false {
                    primary.append(line)
                }
            }
            guard !primary.isEmpty, !latin.isEmpty else { return nil }
            return (labels, primary, latin)
        }
        guard let first = streams(first), let second = streams(second) else { return false }
        return first.labels == second.labels
            && first.primary == second.primary
            && first.latin == second.latin
    }

    private static func hasPairedScripts(_ text: String) -> Bool {
        var previousScript: Bool?
        for line in text.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  Reflow.labelName(of: line) == nil,
                  let isLatin = scriptClass(of: line) else {
                previousScript = nil
                continue
            }
            if let previousScript, previousScript != isLatin { return true }
            previousScript = isLatin
        }
        return false
    }

    private static func scriptClass(of line: String) -> Bool? {
        var hasLatin = false
        var hasNonLatin = false
        for scalar in line.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if isLatinLetter(Int(scalar.value)) {
                hasLatin = true
            } else {
                hasNonLatin = true
            }
            if hasLatin && hasNonLatin { return nil }
        }
        if hasLatin { return true }
        if hasNonLatin { return false }
        return nil
    }

    private static func isLatinLetter(_ value: Int) -> Bool {
        (0x0041...0x024F).contains(value)
            || (0x1E00...0x1EFF).contains(value)
            || (0x2C60...0x2C7F).contains(value)
            || (0xA720...0xA7FF).contains(value)
            || (0xAB30...0xAB6F).contains(value)
    }

    public static func transliterateToLatin(_ text: String) -> String {
        text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false) ?? text
    }

    private static func pairedLyrics(primary: String, additional: [String]) -> String {
        if let paired = pairedLyricsBySection(primary: primary, additional: additional) {
            return paired
        }

        let primaryLines = primary.components(separatedBy: "\n")
        let additionalLines = additional.map { text in
            normalize(text).body.components(separatedBy: .newlines).filter { line in
                !line.trimmingCharacters(in: .whitespaces).isEmpty
                    && Reflow.labelName(of: line) == nil
            }
        }
        var lyricIndex = 0
        var result: [String] = []
        for line in primaryLines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || Reflow.labelName(of: line) != nil {
                result.append(line)
                continue
            }
            result.append(line)
            for languageLines in additionalLines where lyricIndex < languageLines.count {
                result.append(languageLines[lyricIndex])
            }
            lyricIndex += 1
        }
        let remainingCount = additionalLines.map(\.count).max() ?? 0
        if lyricIndex < remainingCount {
            for index in lyricIndex..<remainingCount {
                result.append("")
                for languageLines in additionalLines {
                    if index < languageLines.count { result.append(languageLines[index]) }
                }
            }
        }
        return result.joined(separator: "\n")
    }

    private static func pairedLyricsBySection(
        primary: String, additional: [String]
    ) -> String? {
        let primaryLines = primary.components(separatedBy: "\n")
        let additionalStreams = additional.map { normalize($0).body.components(separatedBy: .newlines) }
        guard primaryLines.contains(where: { Reflow.labelName(of: $0) != nil }),
              additionalStreams.allSatisfy({
                  $0.contains(where: { Reflow.labelName(of: $0) != nil })
              }) else { return nil }

        func sectionKey(_ label: String, occurrence: Int) -> String {
            "\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())#\(occurrence)"
        }

        func linesBySection(_ lines: [String]) -> [String: [String]] {
            var result: [String: [String]] = [:]
            var occurrences: [String: Int] = [:]
            var currentKey = "preamble#0"
            for line in lines {
                if let label = Reflow.labelName(of: line) {
                    let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    occurrences[normalized, default: 0] += 1
                    currentKey = sectionKey(
                        normalized, occurrence: occurrences[normalized, default: 0]
                    )
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[currentKey, default: []].append(line)
                }
            }
            return result
        }

        let additionalBySection = additionalStreams.map(linesBySection)
        var occurrences: [String: Int] = [:]
        var currentKey = "preamble#0"
        var offsets: [String: Int] = [:]
        var result: [String] = []

        for line in primaryLines {
            if let label = Reflow.labelName(of: line) {
                let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                occurrences[normalized, default: 0] += 1
                currentKey = sectionKey(
                    normalized, occurrence: occurrences[normalized, default: 0]
                )
                result.append(line)
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(line)
            } else {
                let offset = offsets[currentKey, default: 0]
                result.append(line)
                for languageLines in additionalBySection {
                    if let pairedLine = languageLines[currentKey], offset < pairedLine.count {
                        result.append(pairedLine[offset])
                    }
                }
                offsets[currentKey] = offset + 1
            }
        }
        return result.joined(separator: "\n")
    }

    public static func normalize(_ text: String, lyricLines: Set<String> = []) -> Normalized {
        let unified = unified(text)

        let chart = ChordChartText.inlined(unified, lyricLines: lyricLines)
        switch detectFormat(unified, lyricLines: lyricLines) {
        case .songSelect:
            var normalized = normalizeSongSelect(chart.text)
            normalized.musicKey = chart.musicKey
            return normalized
        case .chordPro: return normalizeChordPro(unified)
        case .chordChart:
            var normalized = normalizeChordPro(ChordChartText.titled(chart.text))
            normalized.format = .chordChart
            normalized.musicKey = normalized.musicKey ?? chart.musicKey
            return normalized
        case .plainText:
            return Normalized(format: .plainText, body: unified.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func normalizeSongSelect(_ text: String) -> Normalized {
        var lines = text.components(separatedBy: "\n")

        var ccli = CCLIInfo()
        if let footerStart = lines.firstIndex(where: { ccliSongNumberRegex.firstMatch(in: $0) != nil }) {
            let footer = lines[footerStart...].map { $0.trimmingCharacters(in: .whitespaces) }
            lines = Array(lines[..<footerStart])
            for (offset, line) in footer.enumerated() {
                if let number = ccliSongNumberRegex.firstMatch(in: line) {
                    ccli.songNumber = Int(number)

                    let next = footer.dropFirst(offset + 1).first(where: { !$0.isEmpty })
                    if let authors = next, !authors.hasPrefix("©"), !isCCLIBoilerplate(authors) {
                        ccli.author = authors
                    }
                } else if line.hasPrefix("©") {
                    ccli.copyright = (ccli.copyright.map { $0 + "\n" } ?? "") + line
                    if ccli.copyrightYear == nil {
                        ccli.copyrightYear = copyrightYearRegex.firstMatch(in: line).flatMap { Int($0) }
                    }
                }
            }
        }

        var title: String?
        var body: [String] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if title == nil {
                if !line.isEmpty { title = line }
                continue
            }
            body.append(line)
        }
        ccli.songTitle = title

        return Normalized(
            format: .songSelect,
            title: title,
            ccli: ccli == CCLIInfo(songTitle: title) && title == nil ? nil : ccli,
            body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func normalizeChordPro(_ text: String) -> Normalized {
        var title: String?
        var ccli = CCLIInfo()
        var hasCCLI = false
        var musicKey: String?
        var body: [String] = []
        var extraLabels: [String] = []

        func appendLabel(_ label: String) {
            if body.last?.isEmpty == false { body.append("") }
            body.append(label)
            if Reflow.labelName(of: label) == nil, !extraLabels.contains(label) { extraLabels.append(label) }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let directive = chordProDirective(from: line) {
                switch directive.key {
                case "title", "t":
                    title = directive.value
                case "subtitle", "st", "artist", "author":
                    if ccli.author == nil, let value = directive.value {
                        ccli.author = value
                        hasCCLI = true
                    }
                case "copyright":
                    if let value = directive.value {
                        ccli.copyright = value
                        ccli.copyrightYear = copyrightYearRegex.firstMatch(in: value).flatMap { Int($0) }
                        hasCCLI = true
                    }
                case "ccli":
                    if let value = directive.value, let number = Int(value.filter(\.isNumber)), number > 0 {
                        ccli.songNumber = number
                        hasCCLI = true
                    }
                case "comment", "c":

                    if let value = directive.value, let label = Reflow.labelName(of: value) {
                        appendLabel(label)
                    }
                case "start_of_chorus", "soc":
                    appendLabel(directive.value ?? "Chorus")
                case "start_of_verse", "sov":
                    appendLabel(directive.value ?? "Verse")
                case "start_of_bridge", "sob":
                    appendLabel(directive.value ?? "Bridge")
                case "start_of_part":

                    if let value = directive.value { appendLabel(value) }
                case "key":

                    if let value = directive.value, ChordMath.parseKey(value) != nil {
                        musicKey = value
                    }
                default:
                    break  
                }
                continue
            }
            if line.isEmpty {
                if body.last?.isEmpty == false { body.append("") }
                continue
            }
            if Reflow.labelName(of: line) != nil {
                body.append(line)
                continue
            }

            body.append(line)
        }

        return Normalized(
            format: .chordPro,
            title: title,
            ccli: hasCCLI ? ccli : nil,
            chordProSource: text,
            musicKey: musicKey,
            body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            extraLabels: extraLabels
        )
    }

    private static func chordProDirective(from line: String) -> (key: String, value: String?)? {
        guard line.hasPrefix("{"), line.hasSuffix("}") else { return nil }
        let body = String(line.dropFirst().dropLast())
        let parts = body.split(separator: ":", maxSplits: 1)
        guard let key = parts.first else { return nil }
        let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        return (key.trimmingCharacters(in: .whitespaces).lowercased(), value?.isEmpty == true ? nil : value)
    }

    private static func isCCLIBoilerplate(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("songselect")
            || line.localizedCaseInsensitiveContains("ccli licen")
            || line.localizedCaseInsensitiveContains("all rights reserved")
            || line.localizedCaseInsensitiveContains("www.ccli.com")
    }

    private static let ccliSongNumberRegex = SimpleRegex(#"CCLI Song #\s*(\d+)"#, caseInsensitive: true)
    private static let copyrightYearRegex = SimpleRegex(#"(\b(?:19|20)\d{2}\b)"#)
    private static let chordProDirectiveRegex = SimpleRegex(#"^\{[a-zA-Z_]+(:.*)?\}$"#)
    private static let inlineChordRegex = SimpleRegex(#"\[[A-G][#b]?(?:m|maj|min|dim|aug|sus|add)?\d*(?:/[A-G][#b]?)?\]"#)
}

struct SimpleRegex {
    private let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let groupRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let swiftRange = Range(groupRange.location == NSNotFound ? match.range : groupRange, in: text) else { return nil }
        return String(text[swiftRange])
    }

    func wholeMatch(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return match.range == range
    }
}
