import PhotosUI
import SwiftUI

/// Pick old photos from the library (any angle, any era), confirm when each was taken (pre-filled from EXIF),
/// tag the angle, optionally add the weight and a note, then save them as `ProgressPhoto`s.
@MainActor
struct ProgressPhotoImportView: View {
    let onDone: (Int) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var drafts: [PhotoDraft] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var saveError: String?

    struct PhotoDraft: Identifiable {
        let id = UUID()
        let image: UIImage
        var takenAt: Date
        var hadExifDate: Bool
        var angle: ProgressPhotoAngle = .front
        var weightText = ""
        var note = ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: Spacing.m) {
                        intro
                        ForEach($drafts) { $draft in
                            draftCard($draft)
                        }
                        if let loadError { Text(loadError).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger) }
                        if let saveError { Text(saveError).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger) }
                        if !drafts.isEmpty {
                            Button(drafts.count == 1 ? "Add photo" : "Add \(drafts.count) photos", action: save)
                                .buttonStyle(.freeTrackPrimary)
                        }
                    }
                    .padding(Spacing.m)
                    .padding(.bottom, Spacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                if isLoading { LoadingOverlay(message: "Reading photos…") }
            }
            .background(Color.mBackground.ignoresSafeArea())
            .navigationTitle("Add old photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(0) } }
            }
            .keyboardDoneToolbar()
        }
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
        .interactiveDismissDisabled(!drafts.isEmpty)
    }

    // MARK: - Sections

    private var intro: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(drafts.isEmpty ? "Pick photos of yourself" : "Check the dates")
                    .font(FreeTrackFont.headline).foregroundStyle(Color.mText)
                Text(drafts.isEmpty
                     ? "Any angle and any era works — these are for seeing the change with your own eyes, not for measuring. The date is read from each photo when it has one."
                     : "Dates come from the photo's own data when it has it; fix any that are wrong. Tag the angle so Compare can line up matching views.")
                    .font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label(drafts.isEmpty ? "Choose photos" : "Choose more", systemImage: "photo.on.rectangle")
                        .font(FreeTrackFont.headline)
                        .foregroundStyle(drafts.isEmpty ? Color.white : Color.mAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(drafts.isEmpty ? Color.mAccent : Color.mAccentSoft,
                                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                Text("Photos stay on this phone and are never synced.")
                    .font(FreeTrackFont.caption).foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    private func draftCard(_ draft: Binding<PhotoDraft>) -> some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(uiImage: draft.wrappedValue.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    DatePicker("Taken", selection: draft.takenAt, in: ...Date.now, displayedComponents: .date)
                        .font(FreeTrackFont.callout)
                        .foregroundStyle(Color.mText)
                    if !draft.wrappedValue.hadExifDate {
                        Text("No date in this photo — set it yourself.")
                            .font(FreeTrackFont.caption).foregroundStyle(Color.mWarning)
                    }
                    Picker("Angle", selection: draft.angle) {
                        ForEach(ProgressPhotoAngle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Angle")
                    HStack(spacing: Spacing.s) {
                        TextField(settings.unitSystem == .metric ? "Weight (kg)" : "Weight (lb)", text: draft.weightText)
                            .keyboardType(.decimalPad)
                            .font(FreeTrackFont.callout)
                            .foregroundStyle(Color.mText)
                        TextField("Note", text: draft.note)
                            .font(FreeTrackFont.callout)
                            .foregroundStyle(Color.mText)
                    }
                }
                Button {
                    drafts.removeAll { $0.id == draft.wrappedValue.id }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.mTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this photo")
            }
        }
    }

    // MARK: - Actions

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadError = nil
        isLoading = true
        Task { @MainActor in
            defer { pickerItems = []; isLoading = false }
            var unreadable = 0
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let loaded = ProgressPhotoImporter.load(data) else { unreadable += 1; continue }
                // Keep the draft light: the full-size image is stored when saving.
                let preview = ImageResizer.resize(loaded.image, maxDimension: 1600)
                drafts.append(PhotoDraft(image: preview, takenAt: loaded.takenAt ?? .now, hadExifDate: loaded.takenAt != nil))
            }
            if unreadable > 0 {
                loadError = unreadable == 1 ? "One photo couldn't be read and was skipped." : "\(unreadable) photos couldn't be read and were skipped."
            }
        }
    }

    private func save() {
        saveError = nil
        var saved: [ProgressPhoto] = []
        do {
            for draft in drafts {
                let filename = try BodyScanPhotoStore.save(draft.image)
                let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                saved.append(ProgressPhoto(takenAt: draft.takenAt, filename: filename, angle: draft.angle,
                                           note: note.isEmpty ? nil : note, weightKg: weightKg(from: draft.weightText)))
            }
            try context.saveProgressPhotos(saved)
            if settings.hapticsEnabled { Haptics.success() }
            onDone(saved.count)
        } catch {
            for photo in saved { BodyScanPhotoStore.delete(photo.filename) }
            saveError = "Couldn't save these photos. \(error.localizedDescription)"
        }
    }

    private func weightKg(from text: String) -> Double? {
        guard let value = NumberFieldFormat.parse(text), value > 0 else { return nil }
        let kg = settings.unitSystem == .metric ? value : Units.kg(fromLb: value)
        return (25...400).contains(kg) ? kg : nil
    }
}
