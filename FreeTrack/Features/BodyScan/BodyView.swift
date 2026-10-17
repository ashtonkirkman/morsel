import SwiftData
import SwiftUI

/// Body tab: latest scan summary with deltas vs. baseline, progress photos (imported + scan photos, with
/// before/after compare), trend chart, scan list, "New scan".
@MainActor
struct BodyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var scans: [BodyScan] = []
    @State private var photos: [ProgressPhoto] = []
    @State private var loadError: String?
    @State private var showFlow = false
    @State private var showIntro = false
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showCompare = false
    @State private var selectedPhoto: ProgressTimelineItem?
    @State private var importScan: ImportedScanPhoto?
    @State private var chartMetric: BodyMetric = .waistCircumference
    @AppStorage("bodyScanIntroSeen") private var introSeen = false

    private var latest: BodyScan? { scans.first }
    private var baseline: BodyScan? { scans.first { $0.isBaseline } }
    private var timeline: [ProgressTimelineItem] { ProgressTimelineItem.timeline(photos: photos, scans: scans) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if let loadError {
                        errorCard(loadError)
                    } else if scans.isEmpty {
                        emptyState
                        photosCard
                    } else {
                        if let latest { BodyScanSummaryCard(scan: latest, baseline: baseline, unitSystem: settings.unitSystem) }
                        photosCard
                        chartCard
                        scansList
                        newScanButton
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Body scan settings")
                }
            }
            .navigationDestination(for: BodyScan.self) { scan in
                BodyScanDetailView(scan: scan)
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showFlow, onDismiss: load) {
            BodyScanFlowView { _ in showFlow = false }
        }
        .sheet(isPresented: $showIntro) {
            BodyScanIntroSheet {
                introSeen = true
                showIntro = false
                showFlow = true
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            BodyScanSettingsView()
        }
        .sheet(isPresented: $showImport, onDismiss: load) {
            ProgressPhotoImportView { _ in showImport = false }
        }
        .sheet(isPresented: $showCompare) {
            ProgressPhotoCompareView(items: timeline)
        }
        .sheet(item: $selectedPhoto, onDismiss: load) { item in
            ProgressPhotoDetailView(item: item, onMeasure: { image in measure(item, image: image) }, onChanged: load)
        }
        .sheet(item: $importScan, onDismiss: load) { photo in
            BodyScanFlowView(importing: photo) { scan in
                if scan != nil { removeSourcePhoto(photo) }
                importScan = nil
            }
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            EmptyStateView(symbol: "figure.stand",
                           title: "No body scans yet",
                           message: "Up to three photos, analysed on this phone, give you waist, body fat, arm and thigh measurements you can track over time. Head-to-toe gives the most; head-and-shoulders works too.")
            newScanButton
            Text("Photos never leave your phone. Only the numbers are kept — and only synced if you turn on an account.")
                .font(FreeTrackFont.caption)
                .foregroundStyle(Color.mTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.xl)
    }

    private var newScanButton: some View {
        Button(action: startScan) { Label("New scan", systemImage: "camera.viewfinder") }
            .buttonStyle(.freeTrackPrimary)
    }

    private var photosCard: some View {
        ProgressPhotosCard(items: timeline, unitSystem: settings.unitSystem,
                           onAdd: { showImport = true },
                           onCompare: { showCompare = true },
                           onSelect: { selectedPhoto = $0 })
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Trend", trailing: scans.count == 1 ? "1 scan" : "\(scans.count) scans")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(BodyTrendChart.chartMetrics) { metric in
                            Chip(title: metric.title, isSelected: metric == chartMetric) {
                                chartMetric = metric
                                if settings.hapticsEnabled { Haptics.tap() }
                            }
                        }
                    }
                }
                BodyTrendChart(points: trendPoints(for: chartMetric), metric: chartMetric, unitSystem: settings.unitSystem)
                    .frame(height: 200)
            }
        }
    }

    private var scansList: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Scans").padding(.top, Spacing.s)
            ForEach(scans) { scan in
                NavigationLink(value: scan) {
                    BodyScanRow(scan: scan, unitSystem: settings.unitSystem)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !scan.isBaseline {
                        Button { setBaseline(scan) } label: { Label("Set as baseline", systemImage: "flag") }
                    }
                    Button(role: .destructive) { delete(scan) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Couldn't load your scans.").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                Text(message).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                Button("Try again", action: load).buttonStyle(.freeTrackSecondary)
            }
        }
    }

    // MARK: - Data

    private func load() {
        do {
            scans = try context.bodyScans()
            photos = try context.progressPhotos()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Closes the photo sheet, then opens the scan flow on that picture (sheets can't swap in one frame).
    private func measure(_ item: ProgressTimelineItem, image: UIImage) {
        selectedPhoto = nil
        // Re-read the record: the detail sheet may have just corrected the date or weight.
        let source = item.importedID.flatMap { try? context.progressPhoto(id: $0) }
        let photo = ImportedScanPhoto(image: image, takenAt: source?.takenAt ?? item.date,
                                      weightKg: source?.weightKg ?? item.weightKg, sourcePhotoID: item.importedID)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            importScan = photo
        }
    }

    /// The scan keeps its own copy of the picture, so the imported original would only show up twice.
    private func removeSourcePhoto(_ photo: ImportedScanPhoto) {
        guard let id = photo.sourcePhotoID, let source = try? context.progressPhoto(id: id) else { return }
        ProgressThumbnails.forget(source.filename)
        try? context.deleteProgressPhoto(source)
    }

    private func trendPoints(for metric: BodyMetric) -> [BodyTrendPoint] {
        scans.reversed().compactMap { scan in
            guard let v = scan.flattened(metric) else { return nil }
            return BodyTrendPoint(date: scan.createdAt, value: v)
        }
    }

    private func startScan() {
        if introSeen { showFlow = true } else { showIntro = true }
    }

    private func setBaseline(_ scan: BodyScan) {
        try? context.setBaselineBodyScan(scan)
        load()
    }

    private func delete(_ scan: BodyScan) {
        try? context.deleteBodyScan(scan)
        load()
    }
}

// MARK: - Summary card

/// Headline numbers from the latest scan with deltas against the baseline.
struct BodyScanSummaryCard: View {
    let scan: BodyScan
    let baseline: BodyScan?
    let unitSystem: UnitSystem

    private static let metrics: [BodyMetric] = [.waistCircumference, .bodyFatPercent, .leanMassKg,
                                                .leftUpperArmCircumference, .rightUpperArmCircumference,
                                                .leftThighCircumference, .rightThighCircumference]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Latest scan").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Spacer()
                    Text(scan.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                }
                if let waist = scan.waistCm {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(BodyFormat.length(waist, unitSystem))
                            .font(FreeTrackFont.display)
                            .foregroundStyle(Color.mText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("waist").font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                    }
                }
                ForEach(Self.metrics.filter { $0 != .waistCircumference }) { metric in
                    if let value = scan.flattened(metric) {
                        HStack {
                            Text(metric.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                            Spacer()
                            if let base = baseline, base.id != scan.id, let b = base.flattened(metric) {
                                deltaLabel(metric: metric, delta: value - b)
                            }
                            Text(BodyFormat.value(metric, value, unitSystem))
                                .font(FreeTrackFont.numeral)
                                .foregroundStyle(Color.mText)
                        }
                    }
                }
                if let base = baseline, base.id != scan.id {
                    Text("Changes vs. baseline from \(base.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                } else if scan.isBaseline {
                    Text("This is your baseline. Later scans will show changes against it.")
                        .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                }
            }
        }
    }

    private func deltaLabel(metric: BodyMetric, delta: Double) -> some View {
        let change = BodyMetricChange(metric: metric, baseline: 0, current: delta)
        let color: Color = change.isImprovement == nil ? .mTextSecondary : (change.isImprovement == true ? .mAccent : .mWarning)
        return Text(BodyFormat.delta(metric, delta, unitSystem))
            .font(FreeTrackFont.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(abs(delta) < 0.05 ? Color.mTextTertiary : color)
            .padding(.trailing, Spacing.xs)
    }
}

// MARK: - Row

struct BodyScanRow: View {
    let scan: BodyScan
    let unitSystem: UnitSystem

    var body: some View {
        Card {
            HStack(spacing: Spacing.m) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xs) {
                        Text(scan.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(FreeTrackFont.headline)
                            .foregroundStyle(Color.mText)
                        if scan.isBaseline {
                            Text("Baseline")
                                .font(FreeTrackFont.caption.weight(.medium))
                                .foregroundStyle(Color.mAccent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.mAccentSoft, in: Capsule())
                        }
                    }
                    Text(subtitle).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let waist = scan.waistCm {
                        Text(BodyFormat.length(waist, unitSystem)).font(FreeTrackFont.numeral).foregroundStyle(Color.mText)
                        Text("waist").font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [BodyFormat.weight(scan.weightKg, unitSystem)]
        if let bf = scan.bodyFatPercent { parts.append("\(BodyFormat.percent(bf)) fat") }
        if let notes = scan.notes, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = BodyScanPhotoStore.load(scan.frontPhotoFilename ?? scan.tPosePhotoFilename ?? scan.sidePhotoFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "figure.stand")
                .font(.title3)
                .foregroundStyle(Color.mTextTertiary)
                .frame(width: 44, height: 58)
                .background(Color.mSurfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
