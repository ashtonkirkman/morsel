import Foundation

/// Where a food item / log entry came from. Drives small UI hints (icons) and analytics.
enum FoodSource: String, Codable, CaseIterable, Sendable {
    case barcode
    case photo
    case search
    case manual
    case favorite

    var symbolName: String {
        switch self {
        case .barcode: return "barcode.viewfinder"
        case .photo: return "camera"
        case .search: return "magnifyingglass"
        case .manual: return "pencil"
        case .favorite: return "star"
        }
    }
}
