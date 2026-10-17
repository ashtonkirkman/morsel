import SwiftUI

/// "Progress photos" card on the Body tab: a strip of every picture (imported photos and scan photos, oldest
/// first), plus "Add old photos" and "Compare".
struct ProgressPhotosCard: View {
    let items: [ProgressTimelineItem]
    let unitSystem: UnitSystem
    let onAdd: () -> Void
    let onCompare: () -> Void
    let onSelect: (ProgressTimelineItem) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Progress photos", trailing: items.isEmpty ? nil : (items.count == 1 ? "1 photo" : "\(items.count) photos"))
                if items.isEmpty {
                    Text("Add photos of yourself from any time and any angle — old holiday snaps count — and compare them side by side with how you look now.")
                        .font(FreeTrackFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                } else {
                    strip
                    if let span = spanDescription {
                        Text(span).font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                    }
                }
                HStack(spacing: Spacing.s) {
                    Button(action: onAdd) { Label("Add old photos", systemImage: "photo.badge.plus") }
                        .buttonStyle(.freeTrackSecondary)
                    if items.count >= 2 {
                        Button(action: onCompare) { Label("Compare", systemImage: "rectangle.split.2x1") }
                            .buttonStyle(.freeTrackPrimary)
                    }
                }
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        ProgressThumbnail(item: item, width: 72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: item))
                }
            }
        }
    }

    private var spanDescription: String? {
        guard let first = items.first, let last = items.last, first.id != last.id else { return nil }
        let months = Calendar.current.dateComponents([.month], from: first.date, to: last.date).month ?? 0
        let span = months >= 24 ? "\(months / 12) years" : (months >= 1 ? "\(months) month\(months == 1 ? "" : "s")" : "a few weeks")
        var text = "\(first.date.formatted(.dateTime.month(.abbreviated).year())) → \(last.date.formatted(.dateTime.month(.abbreviated).year())) · \(span)"
        if let a = first.weightKg, let b = last.weightKg, abs(a - b) >= 0.05 {
            text += " · \(BodyFormat.weightDelta(b - a, unitSystem))"
        }
        return text
    }

    private func accessibilityLabel(for item: ProgressTimelineItem) -> String {
        "\(item.angle.title) photo from \(item.date.formatted(.dateTime.month(.abbreviated).day().year()))\(item.isFromScan ? ", from a scan" : "")"
    }
}

/// Thumbnail with the date underneath and a small scan marker. `width` sets the size; the box is 3:4.
struct ProgressThumbnail: View {
    let item: ProgressTimelineItem
    var width: CGFloat = 72
    var isSelected = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = ProgressThumbnails.image(for: item.filename) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Color.mTextTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.mSurfaceElevated)
                    }
                }
                .frame(width: width, height: width * 4 / 3)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.mAccent, lineWidth: 3)
                    }
                }
                if item.isFromScan {
                    Image(systemName: "ruler")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.mAccent, in: Circle())
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            Text(item.date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))
                .font(FreeTrackFont.caption)
                .foregroundStyle(isSelected ? Color.mAccent : Color.mTextSecondary)
                .lineLimit(1)
        }
        .frame(width: width)
    }
}
