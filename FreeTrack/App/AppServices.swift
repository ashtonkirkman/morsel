import Foundation
import Observation

/// Concrete service wiring. Features depend on the protocols; only this file names implementations.
@Observable
final class AppServices {
    let barcode: any BarcodeLookupService
    let search: any FoodSearchService
    let vision: any MealVisionService

    init(barcode: any BarcodeLookupService, search: any FoodSearchService, vision: any MealVisionService) {
        self.barcode = barcode
        self.search = search
        self.vision = vision
    }

    convenience init(settings: AppSettings) {
        let openFoodFacts = OpenFoodFactsClient()
        self.init(barcode: openFoodFacts,
                  search: openFoodFacts,
                  vision: ClaudeVisionService(settings: settings))
    }
}
