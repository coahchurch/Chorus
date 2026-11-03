import Foundation

public enum SongLyricsAudit {
    public enum IssueKind: String, Equatable, Sendable {
        case emptySlide
        case unbalancedLanguageLines
    }

    public struct Issue: Equatable, Identifiable, Sendable {
        public let kind: IssueKind
        public let slideName: String
        public let detail: String

        public var id: String { "\(kind.rawValue):\(slideName)" }

        public init(kind: IssueKind, slideName: String, detail: String) {
            self.kind = kind
            self.slideName = slideName
            self.detail = detail
        }
    }

    public static func inspect(_ presentation: Presentation) -> [Issue] {
        guard presentation.presentationKind == .song else { return [] }

        return presentation.slides.flatMap { slide -> [Issue] in
            let lines = slide.objects
                .flatMap { $0.text.components(separatedBy: .newlines) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                return [Issue(
                    kind: .emptySlide,
                    slideName: slide.name,
                    detail: "This song slide has no lyric text."
                )]
            }

            let tamilCount = lines.filter(containsTamil).count
            let englishCount = lines.filter(containsLatin).count
            guard tamilCount > 0, englishCount > 0,
                  abs(tamilCount - englishCount) >= 2,
                  Double(min(tamilCount, englishCount)) / Double(max(tamilCount, englishCount)) < 0.75
            else { return [] }

            return [Issue(
                kind: .unbalancedLanguageLines,
                slideName: slide.name,
                detail: "Found \(tamilCount) Tamil-script lines and \(englishCount) Latin-script lines."
            )]
        }
    }

    private static func containsTamil(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0B80 ... 0x0BFF).contains(Int($0.value)) }
    }

    private static func containsLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x0041 ... 0x005A).contains(Int($0.value))
                || (0x0061 ... 0x007A).contains(Int($0.value))
        }
    }
}
