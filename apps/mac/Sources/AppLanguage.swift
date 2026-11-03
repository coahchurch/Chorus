import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case tamil = "ta"

    var title: String {
        switch self {
        case .english: "English"
        case .tamil: "தமிழ்"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}
