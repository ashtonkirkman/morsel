import SwiftUI

/// One food line: name, serving, calories on the right. Used in Today, search results, review sheets.
struct FoodRow: View {
    let title: String
    var subtitle: String? = nil
    let calories: Double
    var symbol: String? = nil
    var trailingDetail: String? = nil

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(Color.mTextTertiary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MorselFont.body)
                    .foregroundStyle(Color.mText)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.kcal(calories))
                    .font(MorselFont.numeral)
                    .foregroundStyle(Color.mText)
                if let trailingDetail {
                    Text(trailingDetail).font(MorselFont.caption).foregroundStyle(Color.mTextTertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension FoodRow {
    init(food: FoodItem, quantity: Double = 1) {
        self.init(title: food.name,
                  subtitle: [food.brand, quantity == 1 ? food.servingDescription : "\(Format.quantity(quantity)) × \(food.servingDescription)"]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                  calories: food.nutritionPerServing.calories * quantity,
                  symbol: food.source.symbolName)
    }

    init(entry: LogEntry) {
        self.init(title: entry.name,
                  subtitle: [entry.brand, entry.quantity == 1 ? entry.servingDescription : "\(Format.quantity(entry.quantity)) × \(entry.servingDescription)"]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                  calories: entry.total.calories,
                  symbol: entry.source.symbolName)
    }
}
