import Foundation
import ImageIO
import UIKit

/// Turns picked library photos into images plus the date they were taken (from EXIF, when the file has it).
/// Nothing here needs photo-library permission: `PhotosPicker` hands over the file bytes.
enum ProgressPhotoImporter {
    struct Loaded {
        let image: UIImage
        /// EXIF `DateTimeOriginal` (else TIFF `DateTime`), nil when the file carries no date.
        let takenAt: Date?
    }

    static func load(_ data: Data) -> Loaded? {
        guard let image = UIImage(data: data) else { return nil }
        return Loaded(image: image, takenAt: captureDate(in: data))
    }

    /// Reads the capture date out of the file's metadata.
    static func captureDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String, let date = parseExifDate(raw) { return date }
            if let raw = exif[kCGImagePropertyExifDateTimeDigitized] as? String, let date = parseExifDate(raw) { return date }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String, let date = parseExifDate(raw) {
            return date
        }
        return nil
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    private static let exifDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd"
        return f
    }()

    /// EXIF dates look like "2021:06:14 09:30:12" (local time, no zone). Unset fields are all spaces or zeros.
    static func parseExifDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("0000") else { return nil }
        if let date = exifFormatter.date(from: trimmed) { return date }
        if let date = exifDateOnlyFormatter.date(from: String(trimmed.prefix(10))) { return date }
        return nil
    }
}

/// Small downscaled copies of progress/scan photos for strips and grids, so the 1600 px files are not decoded
/// at full size for every thumbnail.
@MainActor
enum ProgressThumbnails {
    private static let cache = NSCache<NSString, UIImage>()
    static let maxDimension: CGFloat = 320

    static func image(for filename: String) -> UIImage? {
        if let hit = cache.object(forKey: filename as NSString) { return hit }
        guard let full = BodyScanPhotoStore.load(filename) else { return nil }
        let small = ImageResizer.resize(full, maxDimension: maxDimension)
        cache.setObject(small, forKey: filename as NSString)
        return small
    }

    static func forget(_ filename: String) {
        cache.removeObject(forKey: filename as NSString)
    }
}
