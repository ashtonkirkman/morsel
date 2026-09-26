import SwiftUI

/// Phase 3: photo, summary, confidence, totals, editable items, clarifying question, meal chips, one Log button.
struct EstimateReviewView: View {
    @Bindable var model: SnapMealViewModel
    let onLog: () -> Void
    let onCancel: () -> Void

    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            list
            if model.isRevising {
                LoadingOverlay(message: "Updating estimate…")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .safeAreaInset(edge: .bottom) { logBar }
    }

    // MARK: - List

    private var list: some View {
        List {
            Group {
                header
                totalsCard
                if let question = model.clarifyingQuestion {
                    ClarifyingQuestionCard(question: question,
                                           answer: $model.answer,
                                           errorMessage: model.reviseErrorMessage,
                                           onSubmit: { model.submitAnswer(vision: services.vision) },
                                           onSkip: { model.skipQuestion() })
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.m, bottom: Spacing.m, trailing: Spacing.m))

            Section {
                ForEach($model.items) { $item in
                    EstimateItemRow(item: $item, isExpanded: model.expandedItemID == item.id) {
                        model.toggleExpanded(item.id)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            model.remove(item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .listRowBackground(Color.mSurfaceElevated)
            } header: {
                SectionHeader(title: "Items", trailing: "Tap to edit · swipe to remove")
                    .textCase(nil)
            }

            mealPicker
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m, bottom: Spacing.xl, trailing: Spacing.m))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.mBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.summary)
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
                    .lineLimit(2)
                ConfidenceBadge(confidence: model.overallConfidence)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.s)
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let total = model.total
        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.kcal(total.calories))
                        .font(MorselFont.display)
                        .foregroundStyle(Color.mText)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                }
                HStack(spacing: Spacing.m) {
                    MacroDot(color: .mProtein, text: "Protein \(Format.grams(total.protein))")
                    MacroDot(color: .mCarbs, text: "Carbs \(Format.grams(total.carbs))")
                    MacroDot(color: .mFat, text: "Fat \(Format.grams(total.fat))")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: total.calories)
    }

    // MARK: - Meal

    private var mealPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Meal")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(MealType.allCases) { meal in
                        Chip(title: meal.title, symbol: meal.symbolName, isSelected: model.mealType == meal) {
                            model.mealType = meal
                        }
                    }
                }
            }
        }
    }

    // MARK: - Log bar

    private var logBar: some View {
        VStack(spacing: Spacing.s) {
            if let message = model.logErrorMessage {
                Text(message)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mDanger)
                    .multilineTextAlignment(.center)
            }
            Button("Log · \(Format.kcalWithUnit(model.total.calories))", action: onLog)
                .buttonStyle(.morselPrimary)
                .disabled(!model.canLog || model.isRevising)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.mBackground)
    }
}

// MARK: - Item row

/// Name, serving, calories, a 0.25-step servings stepper; tap the title to expand the editor.
struct EstimateItemRow: View {
    @Binding var item: EstimatedFoodItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.food.name)
                        .font(MorselFont.body)
                        .foregroundStyle(Color.mText)
                    Text(item.food.servingDescription)
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.kcal(item.total.calories))
                        .font(MorselFont.numeral)
                        .foregroundStyle(Color.mText)
                    Text("kcal")
                        .font(MorselFont.caption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapses the editor" : "Edits calories and serving")

            HStack {
                Text("\(Format.quantity(item.quantity)) × serving")
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Stepper("Servings", value: $item.quantity, in: 0.25...20, step: 0.25)
                    .labelsHidden()
                    .accessibilityLabel("Servings of \(item.food.name)")
            }

            if isExpanded {
                EstimateItemEditor(item: $item)
            }
        }
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

// MARK: - Inline editor

/// Per-serving nutrition and serving fields for one item.
struct EstimateItemEditor: View {
    @Binding var item: EstimatedFoodItem

    var body: some View {
        Card(padding: Spacing.s) {
            VStack(spacing: Spacing.s) {
                textRow("Serving", text: $item.food.servingDescription)
                optionalNumberRow("Grams per serving", value: $item.food.servingGrams)
                numberRow("Calories", value: $item.food.nutritionPerServing.calories)
                numberRow("Protein (g)", value: $item.food.nutritionPerServing.protein)
                numberRow("Carbs (g)", value: $item.food.nutritionPerServing.carbs)
                numberRow("Fat (g)", value: $item.food.nutritionPerServing.fat)
            }
        }
    }

    private func textRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
            Spacer()
            TextField(title, text: text)
                .font(MorselFont.callout)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 180)
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
            Spacer()
            TextField(title, value: value, format: .number)
                .font(MorselFont.numeral)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func optionalNumberRow(_ title: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
                .font(MorselFont.callout)
                .foregroundStyle(Color.mTextSecondary)
            Spacer()
            TextField(title, value: value, format: .number)
                .font(MorselFont.numeral)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }
}

// MARK: - Clarifying question

/// Accent-tinted card: the model's one question, an answer field, Update estimate, Skip.
struct ClarifyingQuestionCard: View {
    let question: String
    @Binding var answer: String
    let errorMessage: String?
    let onSubmit: () -> Void
    let onSkip: () -> Void

    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(question)
                    .font(MorselFont.headline)
                    .foregroundStyle(Color.mText)
            } icon: {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Color.mAccent)
            }
            TextField("Your answer", text: $answer)
                .font(MorselFont.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.mSurface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSubmit { onSubmit() } }
            if let errorMessage {
                Text(errorMessage)
                    .font(MorselFont.caption)
                    .foregroundStyle(Color.mDanger)
            }
            HStack(spacing: Spacing.m) {
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .font(MorselFont.callout.weight(.medium))
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Button("Update estimate", action: onSubmit)
                    .buttonStyle(.morselPrimary)
                    .disabled(!canSubmit)
                    .frame(maxWidth: 220)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mAccentSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
