import SwiftData
import SwiftUI

/// One progress picture full size. Imported photos can have their date, angle, weight and note corrected, be
/// turned into a measured scan dated to the photo, or be deleted. Scan photos just show where they came from.
@MainActor
struct ProgressPhotoDetailView: View {
    let item: ProgressTimelineItem
    /// Called with the full-size image when the person wants to measure an imported photo.
    let onMeasure: (UIImage) -> Void
    let onChanged: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var photo: ProgressPhoto?
    @State private var takenAt: Date = .now
    @State private var angle: ProgressPhotoAngle = .front
    @State private var weightText = ""
    @State private var note = ""
    @State private var showDeleteConfirm = false
    @State private var actionError: String?

    private var image: UIImage? { BodyScanPhotoStore.load(item.filename) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .accessibilityLabel("\(item.angle.title) photo from \(item.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                    } else {
                        EmptyStateView(symbol: "photo", title: "Photo not found", message: "It may have been deleted from this phone.")
                    }
                    if item.isFromScan { scanCard } else { editCard }
                    if let actionError { Text(actionError).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger) }
                    if !item.isFromScan { actions }
                }
                .padding(Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle(item.date.formatted(.dateTime.month(.abbreviated).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveEdits(); dismiss() } }
            }
            .keyboardDoneToolbar()
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive, action: deletePhoto)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the picture from this phone.")
        }
    }

    // MARK: - Cards

    private var scanCard: some View {
        let weight = item.weightKg.map { " at " + BodyFormat.weight($0, settings.unitSystem) } ?? ""
        return Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("From a body scan", systemImage: "ruler").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                Text("Taken \(BodyFormat.scanDate(item.date))\(weight). Open the scan from the list on the Body tab for its measurements.")
                    .font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                if let n = item.note, !n.isEmpty {
                    Text(n).font(FreeTrackFont.caption).foregroundStyle(Color.mTextSecondary)
                }
            }
        }
    }

    private var editCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Details").font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                DatePicker("Taken", selection: $takenAt, in: ...Date.now, displayedComponents: .date)
                    .font(FreeTrackFont.body).foregroundStyle(Color.mText)
                Divider().overlay(Color.mSeparator)
                HStack {
                    Text("Angle").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                    Spacer()
                    Picker("Angle", selection: $angle) {
                        ForEach(ProgressPhotoAngle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Divider().overlay(Color.mSeparator)
                HStack {
                    Text("Weight then").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                    Spacer()
                    TextField("—", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(FreeTrackFont.body.monospacedDigit())
                        .foregroundStyle(Color.mText)
                        .frame(width: 80)
                    Text(settings.unitSystem == .metric ? "kg" : "lb").font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                }
                Divider().overlay(Color.mSeparator)
                TextField("Note (optional)", text: $note)
                    .font(FreeTrackFont.body).foregroundStyle(Color.mText)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.s) {
            Button {
                guard let image else { return }
                saveEdits()
                onMeasure(image)
            } label: {
                Label("Measure this photo as a scan", systemImage: "ruler")
            }
            .buttonStyle(.freeTrackSecondary)
            .disabled(image == nil)
            Text("Works best with a front photo that shows at least your head and shoulders. The scan is dated to this photo, so it appears in your trends.")
                .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary).multilineTextAlignment(.center)
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete photo", systemImage: "trash").foregroundStyle(Color.mDanger)
            }
            .buttonStyle(.freeTrackSecondary)
        }
    }

    // MARK: - Data

    private func load() {
        guard let id = item.importedID, let found = try? context.progressPhoto(id: id) else { return }
        photo = found
        takenAt = found.takenAt
        angle = found.angle
        note = found.note ?? ""
        if let kg = found.weightKg {
            let shown = settings.unitSystem == .metric ? kg : Units.lb(fromKg: kg)
            weightText = NumberFieldFormat.string(shown, fractionDigits: 1)
        }
    }

    /// Writes back any edited field; silently a no-op for scan photos.
    private func saveEdits() {
        guard let photo else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight: Double? = {
            guard let v = NumberFieldFormat.parse(weightText), v > 0 else { return nil }
            let kg = settings.unitSystem == .metric ? v : Units.kg(fromLb: v)
            return (25...400).contains(kg) ? kg : nil
        }()
        let changed = photo.takenAt != takenAt || photo.angle != angle || photo.note != (trimmed.isEmpty ? nil : trimmed) || photo.weightKg != weight
        guard changed else { return }
        photo.takenAt = takenAt
        photo.angle = angle
        photo.note = trimmed.isEmpty ? nil : trimmed
        photo.weightKg = weight
        do {
            try context.save()
            onChanged()
        } catch {
            actionError = "Couldn't save the changes. \(error.localizedDescription)"
        }
    }

    private func deletePhoto() {
        guard let photo else { return }
        do {
            ProgressThumbnails.forget(photo.filename)
            try context.deleteProgressPhoto(photo)
            onChanged()
            dismiss()
        } catch {
            actionError = "Couldn't delete this photo. \(error.localizedDescription)"
        }
    }
}
