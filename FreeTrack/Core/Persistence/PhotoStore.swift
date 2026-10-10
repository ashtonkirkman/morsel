import Foundation
import UIKit

/// Stores meal photos as JPEG files in Application Support/MealPhotos. Entries keep the file name.
struct PhotoStore: Sendable {
    static let shared = PhotoStore()

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MealPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func url(for filename: String) -> URL { directory.appendingPathComponent(filename) }

    /// Downscales to `maxDimension` and writes JPEG. Returns the stored file name.
    @discardableResult
    func save(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) throws -> String {
        let data = try ImageResizer.jpegData(from: image, maxDimension: maxDimension, quality: quality)
        let name = UUID().uuidString + ".jpg"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: url(for: filename).path)
    }

    func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}

enum ImageResizer {
    /// Returns JPEG data with the long edge ≤ `maxDimension`. Good default for API upload.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) throws -> Data {
        let resized = resize(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else { throw ServiceError.invalidImage }
        return data
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
