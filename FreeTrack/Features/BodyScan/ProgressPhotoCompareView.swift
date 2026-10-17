import SwiftUI

/// Before / after: two progress pictures side by side or under a reveal slider, with the dates and weights,
/// filtered by angle so a front photo is compared with a front photo. Defaults to oldest vs. newest.
@MainActor
struct ProgressPhotoCompareView: View {
    let items: [ProgressTimelineItem]
    var initialBefore: ProgressTimelineItem? = nil
    var initialAfter: ProgressTimelineItem? = nil

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var angleFilter: ProgressPhotoAngle?
    @State private var beforeID: String?
    @State private var afterID: String?
    @State private var mode: Mode = .sideBySide
    @State private var revealFraction: CGFloat = 0.5

    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide, slider
        var id: String { rawValue }
        var title: String { self == .sideBySide ? "Side by side" : "Slider" }
    }

    private var filtered: [ProgressTimelineItem] {
        guard let angleFilter else { return items }
        return items.filter { $0.angle == angleFilter }
    }

    private var before: ProgressTimelineItem? { filtered.first { $0.id == beforeID } ?? filtered.first }
    private var after: ProgressTimelineItem? { filtered.first { $0.id == afterID } ?? filtered.last }
    private var anglesPresent: [ProgressPhotoAngle] { ProgressPhotoAngle.allCases.filter { a in items.contains { $0.angle == a } } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if anglesPresent.count > 1 { angleChips }
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Comparison layout")
                    if let before, let after {
                        comparison(before: before, after: after)
                        summaryCard(before: before, after: after)
                    } else {
                        EmptyStateView(symbol: "photo.on.rectangle.angled", title: "Nothing to compare",
                                       message: "Add at least two photos of the same angle.")
                    }
                    picker(title: "Before", selection: $beforeID, current: before)
                    picker(title: "After", selection: $afterID, current: after)
                }
                .padding(Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Then and now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            beforeID = initialBefore?.id ?? items.first?.id
            afterID = initialAfter?.id ?? items.last?.id
            if let initialBefore, initialBefore.angle == initialAfter?.angle, anglesPresent.count > 1 {
                angleFilter = initialBefore.angle
            }
        }
    }

    // MARK: - Pieces

    private var angleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                Chip(title: "All", isSelected: angleFilter == nil) { angleFilter = nil }
                ForEach(anglesPresent) { angle in
                    Chip(title: angle.title, symbol: angle.symbolName, isSelected: angleFilter == angle) {
                        angleFilter = angle
                        if settings.hapticsEnabled { Haptics.tap() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comparison(before: ProgressTimelineItem, after: ProgressTimelineItem) -> some View {
        switch mode {
        case .sideBySide:
            HStack(alignment: .top, spacing: Spacing.s) {
                panel(before, label: "Before")
                panel(after, label: "After")
            }
        case .slider:
            VStack(spacing: Spacing.xs) {
                RevealSlider(before: BodyScanPhotoStore.load(before.filename), after: BodyScanPhotoStore.load(after.filename),
                             fraction: $revealFraction)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                HStack {
                    caption(before, label: "Before", alignment: .leading)
                    Spacer()
                    caption(after, label: "After", alignment: .trailing)
                }
                Text("Drag across the photo to reveal.").font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private func panel(_ item: ProgressTimelineItem, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let image = BodyScanPhotoStore.load(item.filename) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.mSurfaceElevated
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityLabel("\(label) photo, \(item.date.formatted(.dateTime.month(.abbreviated).day().year()))")
            caption(item, label: label, alignment: .leading)
        }
    }

    private func caption(_ item: ProgressTimelineItem, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
            Text(item.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(FreeTrackFont.headline).foregroundStyle(Color.mText)
            if let weight = item.weightKg {
                Text(BodyFormat.weight(weight, settings.unitSystem)).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
            }
        }
    }

    private func summaryCard(before: ProgressTimelineItem, after: ProgressTimelineItem) -> some View {
        let months = Calendar.current.dateComponents([.month], from: min(before.date, after.date), to: max(before.date, after.date)).month ?? 0
        let apart = months >= 24 ? "\(months / 12) years apart" : (months >= 1 ? "\(months) month\(months == 1 ? "" : "s") apart" : "Less than a month apart")
        return Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(apart).font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Spacer()
                    if let a = before.weightKg, let b = after.weightKg {
                        let delta = b - a
                        ChangeBadge(text: BodyFormat.weightDelta(delta, settings.unitSystem),
                                    isImprovement: nil, isNeutral: abs(delta) < 0.05)
                    }
                }
                if before.angle != after.angle {
                    Text("These are different angles (\(before.angle.title.lowercased()) vs. \(after.angle.title.lowercased())). Pick a matching pair for a fair comparison.")
                        .font(FreeTrackFont.caption).foregroundStyle(Color.mWarning)
                }
                if let n = after.note, !n.isEmpty {
                    Text(n).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }

    private func picker(title: String, selection: Binding<String?>, current: ProgressTimelineItem?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(filtered) { item in
                        Button {
                            selection.wrappedValue = item.id
                            if settings.hapticsEnabled { Haptics.tap() }
                        } label: {
                            ProgressThumbnail(item: item, width: 56, isSelected: item.id == current?.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title): \(item.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .accessibilityAddTraits(item.id == current?.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// "After" underneath, "before" on top clipped to the left `fraction` of the width, with a draggable divider.
struct RevealSlider: View {
    let before: UIImage?
    let after: UIImage?
    @Binding var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x = min(max(fraction, 0.02), 0.98) * w
            ZStack(alignment: .leading) {
                photo(after, w, h)
                photo(before, w, h)
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: h)
                    .shadow(radius: 2)
                    .offset(x: x - 1)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(Color.mText))
                    .position(x: x, y: h / 2)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                fraction = min(max(value.location.x / max(w, 1), 0), 1)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after reveal slider")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = min(fraction + 0.1, 1)
                case .decrement: fraction = max(fraction - 0.1, 0)
                @unknown default: break
                }
            }
        }
    }

    @ViewBuilder
    private func photo(_ image: UIImage?, _ w: CGFloat, _ h: CGFloat) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill().frame(width: w, height: h).clipped()
        } else {
            Color.mSurfaceElevated.frame(width: w, height: h)
        }
    }
}
