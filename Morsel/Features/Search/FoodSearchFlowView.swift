import SwiftUI
import SwiftData

/// Search flow: favorites + recents before typing, debounced results while typing,
/// a shared serving editor to confirm, and shortcuts into quick add / manual entry.
struct FoodSearchFlowView: View {
    // MARK: - Inputs

    let onLogged: ([LogEntry]) -> Void

    // MARK: - Environment

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query(sort: \FavoriteFood.useCount, order: .reverse) private var favorites: [FavoriteFood]

    // MARK: - State

    @State private var model = FoodSearchViewModel()
    @State private var recents: [FoodItem] = []
    @State private var path: [SearchRoute] = []
    @State private var mealType: MealType = .suggested()
    @State private var quickAdd: NamedPresentation?
    @State private var manualForm: NamedPresentation?
    @State private var logError: String?

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let logError {
                    Section {
                        InlineErrorView(message: logError)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }
                if model.isSearching {
                    searchSections
                } else {
                    browseSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.mBackground.ignoresSafeArea())
            .searchable(text: $model.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search foods")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onLogged([]) }
                }
            }
            .navigationDestination(for: SearchRoute.self) { route in
                destination(for: route)
            }
            .task(id: model.requestKey) {
                await model.runSearch(using: services.search)
            }
            .task { loadRecents() }
        }
        .sheet(item: $quickAdd) { presentation in
            QuickAddFlowView(prefillName: presentation.name) { entries in
                quickAdd = nil
                if !entries.isEmpty { onLogged(entries) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $manualForm) { presentation in
            NavigationStack {
                ManualFoodFormView(initialName: presentation.name, barcode: nil) { food in
                    manualForm = nil
                    log(food, quantity: 1, favoriteID: nil)
                }
            }
        }
    }

    // MARK: - Browse (no query)

    @ViewBuilder
    private var browseSections: some View {
        if favorites.isEmpty && recents.isEmpty {
            Section {
                EmptyStateView(symbol: "magnifyingglass",
                               title: "Search for a food",
                               message: "Favorites and recently logged foods will show up here.")
                    .listRowBackground(Color.clear)
            }
        }
        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { favorite in
                    favoriteRow(favorite)
                }
            }
            .listRowBackground(Color.mSurface)
        }
        if !recents.isEmpty {
            Section("Recents") {
                ForEach(recents) { food in
                    NavigationLink(value: SearchRoute.serving(food: food, quantity: 1, favoriteID: nil)) {
                        FoodRow(food: food)
                    }
                    .contextMenu { addToFavoritesButton(food) }
                }
            }
            .listRowBackground(Color.mSurface)
        }
    }

    private func favoriteRow(_ favorite: FavoriteFood) -> some View {
        let food = favorite.asFoodItem()
        return NavigationLink(value: SearchRoute.serving(food: food,
                                                         quantity: favorite.defaultQuantity,
                                                         favoriteID: favorite.id)) {
            FoodRow(food: food, quantity: favorite.defaultQuantity)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                removeFavorite(favorite)
            } label: {
                Label("Remove", systemImage: "star.slash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                removeFavorite(favorite)
            } label: {
                Label("Remove from favorites", systemImage: "star.slash")
            }
        }
    }

    // MARK: - Results (typing)

    @ViewBuilder
    private var searchSections: some View {
        if model.isLoading {
            Section {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Searching…")
                        .font(MorselFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        if let message = model.errorMessage {
            Section {
                InlineErrorView(message: message) { model.retry() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        if !model.results.isEmpty {
            Section("Results") {
                ForEach(model.results) { food in
                    NavigationLink(value: SearchRoute.serving(food: food, quantity: 1, favoriteID: nil)) {
                        FoodRow(food: food)
                    }
                    .contextMenu { addToFavoritesButton(food) }
                }
            }
            .listRowBackground(Color.mSurface)
        }
        if model.showsEmptyState {
            Section {
                VStack(spacing: Spacing.s) {
                    EmptyStateView(symbol: "questionmark.circle",
                                   title: "Nothing found",
                                   message: "Try another spelling, or just log the calories.")
                    Button("Quick add instead") {
                        quickAdd = NamedPresentation(name: model.trimmedQuery)
                    }
                    .buttonStyle(.morselPrimary)
                }
                .listRowBackground(Color.clear)
            }
        }
        if model.hasCompletedCurrentQuery {
            Section {
                Button {
                    manualForm = NamedPresentation(name: model.trimmedQuery)
                } label: {
                    Label("Create food “\(model.trimmedQuery)”", systemImage: "plus.circle")
                        .font(MorselFont.body)
                        .foregroundStyle(Color.mAccent)
                        .lineLimit(1)
                }
                .accessibilityHint("Enter nutrition by hand")
            }
            .listRowBackground(Color.mSurface)
        }
    }

    private func addToFavoritesButton(_ food: FoodItem) -> some View {
        Button {
            addToFavorites(food)
        } label: {
            Label(isFavorite(food) ? "Already a favorite" : "Add to favorites", systemImage: "star")
        }
        .disabled(isFavorite(food))
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(for route: SearchRoute) -> some View {
        switch route {
        case .serving(let food, let quantity, let favoriteID):
            ServingEditorView(food: food, initialQuantity: quantity, mealType: $mealType) { confirmed, confirmedQuantity in
                log(confirmed, quantity: confirmedQuantity, favoriteID: favoriteID)
            }
        }
    }

    // MARK: - Data

    private func loadRecents() {
        do {
            recents = try context.recentFoods(limit: 15)
        } catch {
            recents = []
        }
    }

    private func log(_ food: FoodItem, quantity: Double, favoriteID: UUID?) {
        do {
            let entry = try context.log(food, quantity: quantity, mealType: mealType)
            if let favoriteID, let favorite = favorites.first(where: { $0.id == favoriteID }) {
                favorite.markUsed()
                try? context.save()
            }
            onLogged([entry])
        } catch {
            logError = "Couldn't save that entry. Please try again."
            path = []
        }
    }

    private func favoriteKey(_ name: String, _ brand: String?) -> String {
        (name + "|" + (brand ?? "")).lowercased()
    }

    private func isFavorite(_ food: FoodItem) -> Bool {
        let key = favoriteKey(food.name, food.brand)
        return favorites.contains { favoriteKey($0.name, $0.brand) == key }
    }

    private func addToFavorites(_ food: FoodItem) {
        guard !isFavorite(food) else { return }
        Haptics.tap()
        context.insert(FavoriteFood(food: food))
        try? context.save()
    }

    private func removeFavorite(_ favorite: FavoriteFood) {
        context.delete(favorite)
        try? context.save()
    }
}

// MARK: - Routes & presentations

/// Pushed destinations inside the search flow.
enum SearchRoute: Hashable {
    case serving(food: FoodItem, quantity: Double, favoriteID: UUID?)
}

/// Sheet payload carrying a prefilled name (quick add / manual form).
struct NamedPresentation: Identifiable {
    let id = UUID()
    var name: String?
}
