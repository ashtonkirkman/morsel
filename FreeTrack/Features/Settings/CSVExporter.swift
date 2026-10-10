import Foundation

/// Builds a spreadsheet-friendly CSV of log entries. Pure; no I/O except `writeTemporaryFile`.
enum CSVExporter {
    static let header = "date,time,meal,name,brand,serving,quantity,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,source,confidence"

    static func csv(from entries: [LogEntry], calendar: Calendar = .current) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.dateFormat = "HH:mm"

        var lines: [String] = [header]
        for entry in entries.sorted(by: { $0.loggedAt < $1.loggedAt }) {
            let total = entry.total
            let fields: [String] = [
                dateFormatter.string(from: entry.loggedAt),
                timeFormatter.string(from: entry.loggedAt),
                entry.mealType.rawValue,
                entry.name,
                entry.brand ?? "",
                entry.servingDescription,
                number(entry.quantity),
                number(total.calories),
                number(total.protein),
                number(total.carbs),
                number(total.fat),
                total.fiber.map(number) ?? "",
                total.sugar.map(number) ?? "",
                total.sodium.map(number) ?? "",
                entry.source.rawValue,
                entry.confidence.map(number) ?? ""
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quotes a field when it contains a comma, quote or newline (RFC 4180).
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    /// Writes the CSV to the temp directory and returns its URL (for `ShareLink`).
    static func writeTemporaryFile(_ csv: String, filename: String = "morsel-export.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }
}
