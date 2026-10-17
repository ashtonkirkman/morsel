import Foundation
import Observation
import SwiftData

/// Concrete service wiring. Features depend on the protocols; only this file names implementations.
@Observable
final class AppServices {
    let barcode: any BarcodeLookupService
    let search: any FoodSearchService
    let vision: any MealVisionService
    /// Who is signed in; sign-in / sign-out / delete account.
    let account: AccountService
    /// Pushes and pulls every registered `SyncCollection` when signed in.
    let sync: SyncEngine

    init(barcode: any BarcodeLookupService, search: any FoodSearchService, vision: any MealVisionService,
         account: AccountService, sync: SyncEngine) {
        self.barcode = barcode
        self.search = search
        self.vision = vision
        self.account = account
        self.sync = sync
    }

    /// Production wiring. Pass `accountAPI: StubAccountAPI()` (UI tests, previews) to keep the
    /// account layer off the network; pass `container: nil` to disable sync entirely.
    @MainActor
    convenience init(settings: AppSettings, container: ModelContainer?, accountAPI: (any AccountAPI)? = nil) {
        let openFoodFacts = OpenFoodFactsClient()
        let api = accountAPI ?? AccountAPIClient(baseURLProvider: { [weak settings] in
            settings.flatMap { AccountConfig.baseURL(settings: $0) }
        })
        let account = AccountService(api: api, settings: settings)
        let sync = SyncEngine(account: account, settings: settings, container: container)
        SyncCollections.registerAll(on: sync, settings: settings)
        account.onSessionChanged = { [weak sync] in sync?.sessionDidChange() }
        self.init(barcode: openFoodFacts,
                  search: openFoodFacts,
                  vision: OpenAIVisionService(settings: settings),
                  account: account,
                  sync: sync)
    }
}
