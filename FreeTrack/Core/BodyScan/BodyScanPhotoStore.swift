import Foundation
import UIKit

/// Body-scan photos live next to meal photos in `PhotoStore`, distinguished by a `bodyscan-` file prefix.
/// They are never uploaded or synced.
enum BodyScanPhotoStore {
    static let prefix = "bodyscan-"

    /// Saves a JPEG (long edge ≤ 1600 px) and returns its file name.
    static func save(_ image: UIImage) throws -> String {
        let data = try ImageResizer.jpegData(from: image, maxDimension: 1600, quality: 0.85)
        let name = prefix + UUID().uuidString + ".jpg"
        try data.write(to: PhotoStore.shared.url(for: name), options: .atomic)
        return name
    }

    static func load(_ filename: String?) -> UIImage? { PhotoStore.shared.load(filename) }

    static func delete(_ filename: String?) { PhotoStore.shared.delete(filename) }
}
