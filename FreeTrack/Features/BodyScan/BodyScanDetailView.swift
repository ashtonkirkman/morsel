import SwiftData
import SwiftUI

/// One scan: photos with the skeleton overlay, every measurement grouped with confidence badges,
/// compare-with-baseline, set-as-baseline, delete.
@MainActor
struct BodyScanDetailView: View {
    let scan: BodyScan

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: BodyScan?
    @State private var lightboxPose: BodyPoseType?
    @State private var showDeleteConfirm = false
    @State private var actionError: String?

    private var measurements: BodyMeasurements { scan.measurements ?? BodyMeasurements() }
    private var unit: UnitSystem { settings.unitSystem }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                headerCard
                photosStrip
                if let baseline, baseline.id != scan.id {
                    NavigationLink {
                        BodyScanCompareView(baseline: baseline, current: scan)
                    } label: {
                        Label("Compare with baseline", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.freeTrackPrimary)
                }
                ForEach([BodyMetricGroup.circumferences, .composition, .lengths, .widths, .symmetry], id: \.self) { group in
                    let metrics = measurements.metrics(in: group)
                    if !metrics.isEmpty { groupCard(group, metrics: metrics) }
                }
                notesCard
                actions
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.mBackground.ignoresSafeArea())
        .navigationTitle(scan.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { baseline = try? context.baselineBodyScan() }
        .sheet(item: $lightboxPose) { pose in
            PhotoLightbox(scan: scan, pose: pose)
        }
        .confirmationDialog("Delete this scan?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete scan and photos", role: .destructive, action: deleteScan)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the measurements and the three photos from this phone.")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(BodyFormat.scanDate(scan.createdAt)).font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Spacer()
                    if scan.isBaseline {
                        Label("Baseline", systemImage: "flag.fill")
                            .font(FreeTrackFont.caption.weight(.medium))
                            .foregroundStyle(Color.mAccent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.mAccentSoft, in: Capsule())
                    }
                    ConfidenceBadge(confidence: measurements.overallConfidence.score)
                }
                HStack(alignment: .top, spacing: Spacing.l) {
                    stat(BodyFormat.height(scan.heightCm, unit), "height")
                    stat(BodyFormat.weight(scan.weightKg, unit), "weight")
                    if let bf = scan.bodyFatPercent { stat(BodyFormat.percent(bf), "body fat") }
                    if let lean = scan.leanMassKg { stat(BodyFormat.weight(lean, unit), "lean mass") }
                }
                Text(sourceLine).font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private var sourceLine: String {
        var parts = ["\(measurements.poses.count) of 3 poses"]
        if let framing = measurements.framing, framing != .fullBody { parts.append(framing.title.lowercased()) }
        if let name = scan.segmenterName { parts.append(name) }
        if let scale = measurements.scaleSourceTitle { parts.append(scale) }
        return parts.joined(separator: " · ")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(FreeTrackFont.numeral).foregroundStyle(Color.mText).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var photosStrip: some View {
        let available = BodyPoseType.allCases.filter { scan.photoFilename(for: $0) != nil }
        if !available.isEmpty {
            HStack(spacing: Spacing.s) {
                ForEach(available) { pose in
                    Button { lightboxPose = pose } label: {
                        VStack(spacing: 4) {
                            if let image = BodyScanPhotoStore.load(scan.photoFilename(for: pose)) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            }
                            Text(pose.shortName).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(pose.title) photo")
                    .accessibilityHint("Shows the photo with detected joints")
                }
            }
        }
    }

    // MARK: - Groups

    private func groupCard(_ group: BodyMetricGroup, metrics: [BodyMetric]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(group.title).font(FreeTrackFont.headline).foregroundStyle(Color.mText).padding(.bottom, Spacing.xs)
                ForEach(metrics) { metric in
                    if let v = measurements[metric] {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Spacing.s) {
                                Text(metric.title).font(FreeTrackFont.body).foregroundStyle(Color.mText)
                                Spacer()
                                confidenceDot(v.confidence)
                                Text(BodyFormat.value(metric, v.value, unit))
                                    .font(FreeTrackFont.numeral)
                                    .foregroundStyle(Color.mText)
                            }
                            if let hint = metric.hint {
                                Text(hint).font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(metric.title), \(BodyFormat.value(metric, v.value, unit)), \(v.confidence.title) confidence")
                    }
                }
                if group == .composition {
                    Text("Body fat uses Relative Fat Mass (height ÷ waist) and, where the neck is visible, the US Navy tape formula. Photo estimates: ±5–10%. Not medical advice.")
                        .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary).padding(.top, Spacing.xs)
                }
            }
        }
    }

    private func confidenceDot(_ confidence: MeasurementConfidence) -> some View {
        let color: Color = confidence == .high ? .mAccent : (confidence == .medium ? .mWarning : .mDanger)
        return Circle().fill(color).frame(width: 7, height: 7)
            .accessibilityLabel("\(confidence.title) confidence")
    }

    @ViewBuilder
    private var notesCard: some View {
        if let notes = scan.notes, !notes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                    Text(notes).font(FreeTrackFont.body).foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Spacing.s) {
            if let actionError {
                Text(actionError).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger)
            }
            if !scan.isBaseline {
                Button { setBaseline() } label: { Label("Set as baseline", systemImage: "flag") }
                    .buttonStyle(.freeTrackSecondary)
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete scan", systemImage: "trash").foregroundStyle(Color.mDanger)
            }
            .buttonStyle(.freeTrackSecondary)
        }
    }

    private func setBaseline() {
        do {
            try context.setBaselineBodyScan(scan)
            baseline = scan
            if settings.hapticsEnabled { Haptics.success() }
        } catch {
            actionError = "Couldn't update the baseline. \(error.localizedDescription)"
        }
    }

    private func deleteScan() {
        do {
            try context.deleteBodyScan(scan)
            dismiss()
        } catch {
            actionError = "Couldn't delete this scan. \(error.localizedDescription)"
        }
    }
}

// MARK: - Lightbox

/// Full-size photo with the stored joints drawn on top (no mask is stored, so only the skeleton is shown).
struct PhotoLightbox: View {
    let scan: BodyScan
    let pose: BodyPoseType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = BodyScanPhotoStore.load(scan.photoFilename(for: pose)) {
                    ScrollView {
                        PoseOverlayView(image: image, keypoints: scan.keypointsByPose[pose]?.scaled(toWidth: Int(image.size.width), height: Int(image.size.height)))
                            .padding(Spacing.m)
                    }
                } else {
                    EmptyStateView(symbol: "photo", title: "Photo not found", message: "It may have been deleted from this phone.")
                }
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle(pose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
