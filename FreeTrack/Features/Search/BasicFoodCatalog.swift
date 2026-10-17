import Foundation

// MARK: - Built-in whole foods
// A small offline table of unbranded staples (fruit, vegetables, meat, dairy, grains, nuts…)
// so that "banana" or "cheese" answers instantly with a plain, generic entry before any branded
// product. Values are per 100 g from USDA FoodData Central (SR Legacy / Foundation Foods),
// rounded; the serving is the usual household measure for that food.

struct BasicFood: Hashable, Sendable {
    let name: String
    /// Extra words the food should match ("capsicum" for bell pepper, "cheese" for cheddar).
    let aliases: [String]
    let servingDescription: String
    let servingGrams: Double
    let per100g: NutritionFacts

    var asFoodItem: FoodItem {
        FoodItem(name: name,
                 brand: nil,
                 barcode: nil,
                 servingDescription: servingDescription,
                 servingGrams: servingGrams,
                 nutritionPerServing: per100g.scaled(by: servingGrams / 100),
                 source: .generic)
    }
}

enum BasicFoodCatalog {

    /// Most results shown for one query; keeps the generic section short above branded products.
    static let maximumMatches = 8

    /// Foods whose name or aliases match every word of `query` (prefix match per word),
    /// best matches first. Empty for an empty query.
    static func matches(_ query: String) -> [FoodItem] {
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return [] }
        let folded = SearchText.folded(query)

        let scored: [(food: BasicFood, score: Int)] = all.compactMap { food in
            let nameTokens = SearchText.tokens(food.name)
            let aliasTokens = food.aliases.flatMap(SearchText.tokens)
            let haystack = nameTokens + aliasTokens
            let allMatch = tokens.allSatisfy { token in haystack.contains { $0.hasPrefix(token) } }
            guard allMatch else { return nil }

            let foldedName = SearchText.folded(food.name)
            var score = 0
            if foldedName == folded { score += 40 }
            else if foldedName.hasPrefix(folded) { score += 30 }
            else if tokens.allSatisfy({ token in nameTokens.contains { $0.hasPrefix(token) } }) { score += 20 }
            else { score += 10 }  // matched via alias only
            score -= min(9, nameTokens.count)  // shorter, plainer names first
            return (food, score)
        }

        return scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score != rhs.element.score ? lhs.element.score > rhs.element.score : lhs.offset < rhs.offset
            }
            .prefix(maximumMatches)
            .map { $0.element.food.asFoodItem }
    }

    // MARK: Data

    // swiftlint:disable function_parameter_count
    private static func food(_ name: String, _ aliases: [String] = [], serving: String, grams: Double,
                             kcal: Double, p: Double, c: Double, f: Double,
                             fiber: Double? = nil, sugar: Double? = nil, sodium: Double? = nil) -> BasicFood {
        BasicFood(name: name, aliases: aliases, servingDescription: serving, servingGrams: grams,
                  per100g: NutritionFacts(calories: kcal, protein: p, carbs: c, fat: f,
                                          fiber: fiber, sugar: sugar, sodium: sodium))
    }
    // swiftlint:enable function_parameter_count

    static let all: [BasicFood] = fruits + vegetables + proteins + dairy + grains + legumesAndNuts + extras

    private static let fruits: [BasicFood] = [
        food("Apple", ["fruit"], serving: "1 medium (182 g)", grams: 182, kcal: 52, p: 0.3, c: 13.8, f: 0.2, fiber: 2.4, sugar: 10.4, sodium: 1),
        food("Banana", ["fruit"], serving: "1 medium (118 g)", grams: 118, kcal: 89, p: 1.1, c: 22.8, f: 0.3, fiber: 2.6, sugar: 12.2, sodium: 1),
        food("Orange", ["fruit"], serving: "1 medium (131 g)", grams: 131, kcal: 47, p: 0.9, c: 11.8, f: 0.1, fiber: 2.4, sugar: 9.4, sodium: 0),
        food("Strawberries", ["strawberry", "berries", "fruit"], serving: "1 cup (152 g)", grams: 152, kcal: 32, p: 0.7, c: 7.7, f: 0.3, fiber: 2.0, sugar: 4.9, sodium: 1),
        food("Blueberries", ["blueberry", "berries", "fruit"], serving: "1 cup (148 g)", grams: 148, kcal: 57, p: 0.7, c: 14.5, f: 0.3, fiber: 2.4, sugar: 10.0, sodium: 1),
        food("Raspberries", ["raspberry", "berries", "fruit"], serving: "1 cup (123 g)", grams: 123, kcal: 52, p: 1.2, c: 11.9, f: 0.7, fiber: 6.5, sugar: 4.4, sodium: 1),
        food("Blackberries", ["blackberry", "berries", "fruit"], serving: "1 cup (144 g)", grams: 144, kcal: 43, p: 1.4, c: 9.6, f: 0.5, fiber: 5.3, sugar: 4.9, sodium: 1),
        food("Grapes", ["grape", "fruit"], serving: "1 cup (151 g)", grams: 151, kcal: 69, p: 0.7, c: 18.1, f: 0.2, fiber: 0.9, sugar: 15.5, sodium: 2),
        food("Watermelon", ["melon", "fruit"], serving: "1 cup diced (152 g)", grams: 152, kcal: 30, p: 0.6, c: 7.6, f: 0.2, fiber: 0.4, sugar: 6.2, sodium: 1),
        food("Cantaloupe", ["melon", "fruit"], serving: "1 cup diced (160 g)", grams: 160, kcal: 34, p: 0.8, c: 8.2, f: 0.2, fiber: 0.9, sugar: 7.9, sodium: 16),
        food("Honeydew melon", ["fruit"], serving: "1 cup diced (170 g)", grams: 170, kcal: 36, p: 0.5, c: 9.1, f: 0.1, fiber: 0.8, sugar: 8.1, sodium: 18),
        food("Pineapple", ["fruit"], serving: "1 cup chunks (165 g)", grams: 165, kcal: 50, p: 0.5, c: 13.1, f: 0.1, fiber: 1.4, sugar: 9.9, sodium: 1),
        food("Mango", ["fruit"], serving: "1 cup pieces (165 g)", grams: 165, kcal: 60, p: 0.8, c: 15.0, f: 0.4, fiber: 1.6, sugar: 13.7, sodium: 1),
        food("Peach", ["fruit"], serving: "1 medium (150 g)", grams: 150, kcal: 39, p: 0.9, c: 9.5, f: 0.3, fiber: 1.5, sugar: 8.4, sodium: 0),
        food("Nectarine", ["fruit"], serving: "1 medium (142 g)", grams: 142, kcal: 44, p: 1.1, c: 10.6, f: 0.3, fiber: 1.7, sugar: 7.9, sodium: 0),
        food("Pear", ["fruit"], serving: "1 medium (178 g)", grams: 178, kcal: 57, p: 0.4, c: 15.2, f: 0.1, fiber: 3.1, sugar: 9.8, sodium: 1),
        food("Plum", ["fruit"], serving: "1 fruit (66 g)", grams: 66, kcal: 46, p: 0.7, c: 11.4, f: 0.3, fiber: 1.4, sugar: 9.9, sodium: 0),
        food("Apricot", ["fruit"], serving: "1 fruit (35 g)", grams: 35, kcal: 48, p: 1.4, c: 11.1, f: 0.4, fiber: 2.0, sugar: 9.2, sodium: 1),
        food("Cherries", ["cherry", "fruit"], serving: "1 cup (138 g)", grams: 138, kcal: 63, p: 1.1, c: 16.0, f: 0.2, fiber: 2.1, sugar: 12.8, sodium: 0),
        food("Kiwi", ["kiwifruit", "fruit"], serving: "1 fruit (69 g)", grams: 69, kcal: 61, p: 1.1, c: 14.7, f: 0.5, fiber: 3.0, sugar: 9.0, sodium: 3),
        food("Avocado", ["fruit"], serving: "½ avocado (100 g)", grams: 100, kcal: 160, p: 2.0, c: 8.5, f: 14.7, fiber: 6.7, sugar: 0.7, sodium: 7),
        food("Grapefruit", ["fruit"], serving: "½ fruit (123 g)", grams: 123, kcal: 42, p: 0.8, c: 10.7, f: 0.1, fiber: 1.6, sugar: 6.9, sodium: 0),
        food("Clementine", ["mandarin", "tangerine", "fruit"], serving: "1 fruit (74 g)", grams: 74, kcal: 47, p: 0.9, c: 12.0, f: 0.2, fiber: 1.7, sugar: 9.2, sodium: 1),
        food("Lemon", ["fruit"], serving: "1 fruit (58 g)", grams: 58, kcal: 29, p: 1.1, c: 9.3, f: 0.3, fiber: 2.8, sugar: 2.5, sodium: 2),
        food("Lime", ["fruit"], serving: "1 fruit (67 g)", grams: 67, kcal: 30, p: 0.7, c: 10.5, f: 0.2, fiber: 2.8, sugar: 1.7, sodium: 2),
        food("Papaya", ["fruit"], serving: "1 cup pieces (145 g)", grams: 145, kcal: 43, p: 0.5, c: 10.8, f: 0.3, fiber: 1.7, sugar: 7.8, sodium: 8),
        food("Pomegranate", ["arils", "fruit"], serving: "½ cup arils (87 g)", grams: 87, kcal: 83, p: 1.7, c: 18.7, f: 1.2, fiber: 4.0, sugar: 13.7, sodium: 3),
        food("Fig", ["figs", "fruit"], serving: "1 fig (50 g)", grams: 50, kcal: 74, p: 0.8, c: 19.2, f: 0.3, fiber: 2.9, sugar: 16.3, sodium: 1),
        food("Dates", ["date", "medjool", "fruit"], serving: "1 medjool date (24 g)", grams: 24, kcal: 277, p: 1.8, c: 75.0, f: 0.2, fiber: 6.7, sugar: 66.5, sodium: 1),
        food("Raisins", ["raisin", "fruit"], serving: "¼ cup (41 g)", grams: 41, kcal: 299, p: 3.1, c: 79.2, f: 0.5, fiber: 3.7, sugar: 59.2, sodium: 11),
        food("Cranberries", ["cranberry", "berries", "fruit"], serving: "1 cup (100 g)", grams: 100, kcal: 46, p: 0.5, c: 12.2, f: 0.1, fiber: 3.6, sugar: 4.3, sodium: 2),
        food("Coconut", ["fruit"], serving: "1 oz raw (28 g)", grams: 28, kcal: 354, p: 3.3, c: 15.2, f: 33.5, fiber: 9.0, sugar: 6.2, sodium: 20)
    ]

    private static let vegetables: [BasicFood] = [
        food("Broccoli", ["vegetable"], serving: "1 cup chopped (91 g)", grams: 91, kcal: 34, p: 2.8, c: 6.6, f: 0.4, fiber: 2.6, sugar: 1.7, sodium: 33),
        food("Carrot", ["carrots", "vegetable"], serving: "1 medium (61 g)", grams: 61, kcal: 41, p: 0.9, c: 9.6, f: 0.2, fiber: 2.8, sugar: 4.7, sodium: 69),
        food("Spinach", ["greens", "vegetable"], serving: "1 cup raw (30 g)", grams: 30, kcal: 23, p: 2.9, c: 3.6, f: 0.4, fiber: 2.2, sugar: 0.4, sodium: 79),
        food("Kale", ["greens", "vegetable"], serving: "1 cup chopped (67 g)", grams: 67, kcal: 49, p: 4.3, c: 8.8, f: 0.9, fiber: 3.6, sugar: 2.3, sodium: 38),
        food("Romaine lettuce", ["salad", "greens", "vegetable"], serving: "1 cup shredded (47 g)", grams: 47, kcal: 17, p: 1.2, c: 3.3, f: 0.3, fiber: 2.1, sugar: 1.2, sodium: 8),
        food("Iceberg lettuce", ["salad", "greens", "vegetable"], serving: "1 cup shredded (72 g)", grams: 72, kcal: 14, p: 0.9, c: 3.0, f: 0.1, fiber: 1.2, sugar: 2.0, sodium: 10),
        food("Arugula", ["rocket", "salad", "greens", "vegetable"], serving: "1 cup (20 g)", grams: 20, kcal: 25, p: 2.6, c: 3.7, f: 0.7, fiber: 1.6, sugar: 2.1, sodium: 27),
        food("Tomato", ["tomatoes", "vegetable"], serving: "1 medium (123 g)", grams: 123, kcal: 18, p: 0.9, c: 3.9, f: 0.2, fiber: 1.2, sugar: 2.6, sodium: 5),
        food("Cherry tomatoes", ["tomato", "vegetable"], serving: "1 cup (149 g)", grams: 149, kcal: 18, p: 0.9, c: 3.9, f: 0.2, fiber: 1.2, sugar: 2.6, sodium: 5),
        food("Cucumber", ["vegetable"], serving: "1 cup sliced (104 g)", grams: 104, kcal: 15, p: 0.7, c: 3.6, f: 0.1, fiber: 0.5, sugar: 1.7, sodium: 2),
        food("Red bell pepper", ["pepper", "capsicum", "vegetable"], serving: "1 medium (119 g)", grams: 119, kcal: 31, p: 1.0, c: 6.0, f: 0.3, fiber: 2.1, sugar: 4.2, sodium: 4),
        food("Green bell pepper", ["pepper", "capsicum", "vegetable"], serving: "1 medium (119 g)", grams: 119, kcal: 20, p: 0.9, c: 4.6, f: 0.2, fiber: 1.7, sugar: 2.4, sodium: 3),
        food("Onion", ["onions", "vegetable"], serving: "1 medium (110 g)", grams: 110, kcal: 40, p: 1.1, c: 9.3, f: 0.1, fiber: 1.7, sugar: 4.2, sodium: 4),
        food("Garlic", ["vegetable"], serving: "1 clove (3 g)", grams: 3, kcal: 149, p: 6.4, c: 33.1, f: 0.5, fiber: 2.1, sugar: 1.0, sodium: 17),
        food("Potato, baked", ["potatoes", "vegetable"], serving: "1 medium with skin (173 g)", grams: 173, kcal: 93, p: 2.5, c: 21.2, f: 0.1, fiber: 2.2, sugar: 1.2, sodium: 10),
        food("Sweet potato, baked", ["yam", "vegetable"], serving: "1 medium with skin (114 g)", grams: 114, kcal: 90, p: 2.0, c: 20.7, f: 0.2, fiber: 3.3, sugar: 6.5, sodium: 36),
        food("Corn, sweet", ["vegetable"], serving: "1 ear, cooked (103 g)", grams: 103, kcal: 96, p: 3.4, c: 21.0, f: 1.5, fiber: 2.4, sugar: 4.5, sodium: 1),
        food("Green peas", ["pea", "vegetable"], serving: "1 cup cooked (160 g)", grams: 160, kcal: 84, p: 5.4, c: 15.6, f: 0.2, fiber: 5.5, sugar: 5.9, sodium: 3),
        food("Green beans", ["string beans", "vegetable"], serving: "1 cup (100 g)", grams: 100, kcal: 31, p: 1.8, c: 7.0, f: 0.2, fiber: 2.7, sugar: 3.3, sodium: 6),
        food("Celery", ["vegetable"], serving: "1 stalk (40 g)", grams: 40, kcal: 14, p: 0.7, c: 3.0, f: 0.2, fiber: 1.6, sugar: 1.3, sodium: 80),
        food("Cauliflower", ["vegetable"], serving: "1 cup chopped (107 g)", grams: 107, kcal: 25, p: 1.9, c: 5.0, f: 0.3, fiber: 2.0, sugar: 1.9, sodium: 30),
        food("Cabbage", ["vegetable"], serving: "1 cup chopped (89 g)", grams: 89, kcal: 25, p: 1.3, c: 5.8, f: 0.1, fiber: 2.5, sugar: 3.2, sodium: 18),
        food("Brussels sprouts", ["vegetable"], serving: "1 cup cooked (156 g)", grams: 156, kcal: 36, p: 2.6, c: 7.1, f: 0.5, fiber: 2.6, sugar: 1.7, sodium: 21),
        food("Asparagus", ["vegetable"], serving: "1 cup cooked (180 g)", grams: 180, kcal: 22, p: 2.4, c: 4.1, f: 0.2, fiber: 2.0, sugar: 1.3, sodium: 14),
        food("Zucchini", ["courgette", "vegetable"], serving: "1 medium (196 g)", grams: 196, kcal: 17, p: 1.2, c: 3.1, f: 0.3, fiber: 1.0, sugar: 2.5, sodium: 8),
        food("Mushrooms", ["mushroom", "vegetable"], serving: "1 cup sliced (70 g)", grams: 70, kcal: 22, p: 3.1, c: 3.3, f: 0.3, fiber: 1.0, sugar: 2.0, sodium: 5),
        food("Eggplant", ["aubergine", "vegetable"], serving: "1 cup cooked (99 g)", grams: 99, kcal: 35, p: 0.8, c: 8.7, f: 0.2, fiber: 2.5, sugar: 3.2, sodium: 1),
        food("Beets", ["beet", "beetroot", "vegetable"], serving: "1 cup cooked (170 g)", grams: 170, kcal: 44, p: 1.7, c: 10.0, f: 0.2, fiber: 2.0, sugar: 8.0, sodium: 77),
        food("Butternut squash", ["vegetable"], serving: "1 cup cubed, baked (205 g)", grams: 205, kcal: 40, p: 0.9, c: 10.5, f: 0.1, fiber: 3.2, sugar: 2.0, sodium: 4),
        food("Edamame", ["soybeans", "vegetable"], serving: "1 cup shelled (155 g)", grams: 155, kcal: 121, p: 11.9, c: 8.9, f: 5.2, fiber: 5.2, sugar: 2.2, sodium: 6),
        food("Radishes", ["radish", "vegetable"], serving: "1 cup sliced (116 g)", grams: 116, kcal: 16, p: 0.7, c: 3.4, f: 0.1, fiber: 1.6, sugar: 1.9, sodium: 39)
    ]

    private static let proteins: [BasicFood] = [
        food("Egg", ["eggs", "boiled egg"], serving: "1 large (50 g)", grams: 50, kcal: 155, p: 12.6, c: 1.1, f: 10.6, fiber: 0, sugar: 1.1, sodium: 124),
        food("Egg white", ["egg whites"], serving: "1 large (33 g)", grams: 33, kcal: 52, p: 10.9, c: 0.7, f: 0.2, fiber: 0, sugar: 0.7, sodium: 166),
        food("Chicken breast", ["chicken", "meat"], serving: "4 oz cooked, skinless (113 g)", grams: 113, kcal: 165, p: 31.0, c: 0, f: 3.6, fiber: 0, sugar: 0, sodium: 74),
        food("Chicken thigh", ["chicken", "meat"], serving: "4 oz cooked, skinless (113 g)", grams: 113, kcal: 209, p: 25.9, c: 0, f: 10.9, fiber: 0, sugar: 0, sodium: 95),
        food("Turkey breast", ["turkey", "meat"], serving: "4 oz roasted (113 g)", grams: 113, kcal: 135, p: 30.1, c: 0, f: 0.7, fiber: 0, sugar: 0, sodium: 52),
        food("Ground beef, 85% lean", ["hamburger", "beef", "meat"], serving: "4 oz cooked (113 g)", grams: 113, kcal: 250, p: 25.9, c: 0, f: 15.4, fiber: 0, sugar: 0, sodium: 72),
        food("Sirloin steak", ["steak", "beef", "meat"], serving: "4 oz broiled (113 g)", grams: 113, kcal: 212, p: 28.9, c: 0, f: 9.9, fiber: 0, sugar: 0, sodium: 59),
        food("Pork chop", ["pork", "meat"], serving: "4 oz broiled (113 g)", grams: 113, kcal: 210, p: 27.0, c: 0, f: 11.0, fiber: 0, sugar: 0, sodium: 60),
        food("Bacon", ["pork"], serving: "1 slice cooked (8 g)", grams: 8, kcal: 541, p: 37.0, c: 1.4, f: 41.8, fiber: 0, sugar: 0, sodium: 2310),
        food("Salmon", ["fish"], serving: "4 oz cooked (113 g)", grams: 113, kcal: 206, p: 22.1, c: 0, f: 12.4, fiber: 0, sugar: 0, sodium: 61),
        food("Tuna, canned in water", ["fish"], serving: "3 oz drained (85 g)", grams: 85, kcal: 116, p: 25.5, c: 0, f: 0.8, fiber: 0, sugar: 0, sodium: 338),
        food("Shrimp", ["prawns", "seafood"], serving: "3 oz cooked (85 g)", grams: 85, kcal: 99, p: 24.0, c: 0.2, f: 0.3, fiber: 0, sugar: 0, sodium: 111),
        food("Tofu, firm", ["bean curd"], serving: "½ cup (126 g)", grams: 126, kcal: 144, p: 17.3, c: 2.8, f: 8.7, fiber: 2.3, sugar: 0.3, sodium: 14)
    ]

    private static let dairy: [BasicFood] = [
        food("Whole milk", ["milk"], serving: "1 cup (244 g)", grams: 244, kcal: 61, p: 3.2, c: 4.8, f: 3.3, fiber: 0, sugar: 5.1, sodium: 43),
        food("2% milk", ["milk", "reduced fat milk"], serving: "1 cup (244 g)", grams: 244, kcal: 50, p: 3.3, c: 4.8, f: 2.0, fiber: 0, sugar: 5.1, sodium: 41),
        food("Skim milk", ["milk", "nonfat milk", "fat free milk"], serving: "1 cup (245 g)", grams: 245, kcal: 34, p: 3.4, c: 5.0, f: 0.1, fiber: 0, sugar: 5.1, sodium: 42),
        food("Greek yogurt, plain nonfat", ["yoghurt"], serving: "1 container (170 g)", grams: 170, kcal: 59, p: 10.2, c: 3.6, f: 0.4, fiber: 0, sugar: 3.2, sodium: 36),
        food("Yogurt, plain whole milk", ["yoghurt"], serving: "1 cup (245 g)", grams: 245, kcal: 61, p: 3.5, c: 4.7, f: 3.3, fiber: 0, sugar: 4.7, sodium: 46),
        food("Cheddar cheese", ["cheese"], serving: "1 oz (28 g)", grams: 28, kcal: 403, p: 24.9, c: 1.3, f: 33.1, fiber: 0, sugar: 0.5, sodium: 621),
        food("Mozzarella cheese, part skim", ["cheese"], serving: "1 oz (28 g)", grams: 28, kcal: 254, p: 24.3, c: 2.8, f: 15.9, fiber: 0, sugar: 1.1, sodium: 619),
        food("Swiss cheese", ["cheese"], serving: "1 oz (28 g)", grams: 28, kcal: 380, p: 26.9, c: 5.4, f: 27.8, fiber: 0, sugar: 1.3, sodium: 192),
        food("American cheese", ["cheese", "processed cheese"], serving: "1 slice (21 g)", grams: 21, kcal: 371, p: 18.1, c: 4.8, f: 30.7, fiber: 0, sugar: 2.6, sodium: 1300),
        food("Parmesan cheese", ["cheese"], serving: "1 tbsp grated (5 g)", grams: 5, kcal: 431, p: 38.5, c: 4.1, f: 28.6, fiber: 0, sugar: 0.9, sodium: 1529),
        food("Feta cheese", ["cheese"], serving: "1 oz (28 g)", grams: 28, kcal: 264, p: 14.2, c: 4.1, f: 21.3, fiber: 0, sugar: 4.1, sodium: 1116),
        food("Cottage cheese, 2%", ["cheese"], serving: "½ cup (113 g)", grams: 113, kcal: 81, p: 10.5, c: 4.8, f: 2.3, fiber: 0, sugar: 4.1, sodium: 330),
        food("Cream cheese", ["cheese"], serving: "1 tbsp (14 g)", grams: 14, kcal: 342, p: 5.9, c: 4.1, f: 34.2, fiber: 0, sugar: 3.2, sodium: 321),
        food("Butter", [], serving: "1 tbsp (14 g)", grams: 14, kcal: 717, p: 0.9, c: 0.1, f: 81.1, fiber: 0, sugar: 0.1, sodium: 643),
        food("Heavy cream", ["whipping cream"], serving: "1 tbsp (15 g)", grams: 15, kcal: 340, p: 2.8, c: 2.8, f: 36.1, fiber: 0, sugar: 2.9, sodium: 27)
    ]

    private static let grains: [BasicFood] = [
        food("White rice, cooked", ["rice"], serving: "1 cup (158 g)", grams: 158, kcal: 130, p: 2.7, c: 28.2, f: 0.3, fiber: 0.4, sugar: 0.1, sodium: 1),
        food("Brown rice, cooked", ["rice"], serving: "1 cup (195 g)", grams: 195, kcal: 123, p: 2.7, c: 25.6, f: 1.0, fiber: 1.6, sugar: 0.2, sodium: 4),
        food("Oats, dry", ["oatmeal", "rolled oats", "porridge"], serving: "½ cup (40 g)", grams: 40, kcal: 379, p: 13.2, c: 67.7, f: 6.5, fiber: 10.1, sugar: 1.0, sodium: 6),
        food("Oatmeal, cooked with water", ["oats", "porridge"], serving: "1 cup (234 g)", grams: 234, kcal: 71, p: 2.5, c: 12.0, f: 1.5, fiber: 1.7, sugar: 0.3, sodium: 4),
        food("Quinoa, cooked", [], serving: "1 cup (185 g)", grams: 185, kcal: 120, p: 4.4, c: 21.3, f: 1.9, fiber: 2.8, sugar: 0.9, sodium: 7),
        food("Pasta, cooked", ["spaghetti", "noodles", "penne"], serving: "1 cup (140 g)", grams: 140, kcal: 158, p: 5.8, c: 30.9, f: 0.9, fiber: 1.8, sugar: 0.6, sodium: 1),
        food("White bread", ["bread", "toast"], serving: "1 slice (27 g)", grams: 27, kcal: 266, p: 7.6, c: 49.2, f: 3.3, fiber: 2.7, sugar: 5.3, sodium: 490),
        food("Whole wheat bread", ["bread", "toast", "wholemeal"], serving: "1 slice (32 g)", grams: 32, kcal: 252, p: 12.5, c: 42.7, f: 3.5, fiber: 6.0, sugar: 4.3, sodium: 455),
        food("Bagel, plain", ["bagels"], serving: "1 medium (105 g)", grams: 105, kcal: 250, p: 10.0, c: 48.9, f: 1.5, fiber: 2.3, sugar: 5.4, sodium: 430),
        food("Flour tortilla", ["tortillas", "wrap"], serving: "1 tortilla, 8 in (45 g)", grams: 45, kcal: 312, p: 8.2, c: 51.0, f: 8.0, fiber: 3.0, sugar: 2.6, sodium: 600),
        food("Corn tortilla", ["tortillas"], serving: "1 tortilla, 6 in (26 g)", grams: 26, kcal: 218, p: 5.7, c: 44.6, f: 2.9, fiber: 6.3, sugar: 0.9, sodium: 45),
        food("Popcorn, air-popped", [], serving: "1 cup (8 g)", grams: 8, kcal: 387, p: 12.9, c: 77.8, f: 4.5, fiber: 14.5, sugar: 0.9, sodium: 8)
    ]

    private static let legumesAndNuts: [BasicFood] = [
        food("Black beans, cooked", ["beans"], serving: "1 cup (172 g)", grams: 172, kcal: 132, p: 8.9, c: 23.7, f: 0.5, fiber: 8.7, sugar: 0.3, sodium: 1),
        food("Kidney beans, cooked", ["beans"], serving: "1 cup (177 g)", grams: 177, kcal: 127, p: 8.7, c: 22.8, f: 0.5, fiber: 6.4, sugar: 0.3, sodium: 2),
        food("Pinto beans, cooked", ["beans"], serving: "1 cup (171 g)", grams: 171, kcal: 143, p: 9.0, c: 26.2, f: 0.7, fiber: 9.0, sugar: 0.3, sodium: 1),
        food("Chickpeas, cooked", ["garbanzo beans", "beans"], serving: "1 cup (164 g)", grams: 164, kcal: 164, p: 8.9, c: 27.4, f: 2.6, fiber: 7.6, sugar: 4.8, sodium: 7),
        food("Lentils, cooked", ["lentil"], serving: "1 cup (198 g)", grams: 198, kcal: 116, p: 9.0, c: 20.1, f: 0.4, fiber: 7.9, sugar: 1.8, sodium: 2),
        food("Hummus", [], serving: "2 tbsp (30 g)", grams: 30, kcal: 166, p: 7.9, c: 14.3, f: 9.6, fiber: 6.0, sugar: 0.3, sodium: 379),
        food("Peanut butter", ["nut butter"], serving: "2 tbsp (32 g)", grams: 32, kcal: 588, p: 25.1, c: 20.0, f: 50.0, fiber: 6.0, sugar: 9.2, sodium: 459),
        food("Almonds", ["almond", "nuts"], serving: "1 oz, about 23 nuts (28 g)", grams: 28, kcal: 579, p: 21.2, c: 21.6, f: 49.9, fiber: 12.5, sugar: 4.4, sodium: 1),
        food("Walnuts", ["walnut", "nuts"], serving: "1 oz, about 14 halves (28 g)", grams: 28, kcal: 654, p: 15.2, c: 13.7, f: 65.2, fiber: 6.7, sugar: 2.6, sodium: 2),
        food("Peanuts", ["peanut", "nuts"], serving: "1 oz dry roasted (28 g)", grams: 28, kcal: 585, p: 23.7, c: 21.5, f: 49.7, fiber: 8.0, sugar: 4.2, sodium: 6),
        food("Cashews", ["cashew", "nuts"], serving: "1 oz (28 g)", grams: 28, kcal: 553, p: 18.2, c: 30.2, f: 43.9, fiber: 3.3, sugar: 5.9, sodium: 12),
        food("Pistachios", ["pistachio", "nuts"], serving: "1 oz, about 49 kernels (28 g)", grams: 28, kcal: 562, p: 20.3, c: 27.5, f: 45.4, fiber: 10.3, sugar: 7.7, sodium: 1),
        food("Pecans", ["pecan", "nuts"], serving: "1 oz, about 19 halves (28 g)", grams: 28, kcal: 691, p: 9.2, c: 13.9, f: 72.0, fiber: 9.6, sugar: 4.0, sodium: 0),
        food("Sunflower seeds", ["seeds"], serving: "1 oz (28 g)", grams: 28, kcal: 584, p: 20.8, c: 20.0, f: 51.5, fiber: 8.6, sugar: 2.6, sodium: 9),
        food("Chia seeds", ["seeds"], serving: "1 oz (28 g)", grams: 28, kcal: 486, p: 16.5, c: 42.1, f: 30.7, fiber: 34.4, sugar: 0, sodium: 16)
    ]

    private static let extras: [BasicFood] = [
        food("Olive oil", ["oil"], serving: "1 tbsp (14 g)", grams: 14, kcal: 884, p: 0, c: 0, f: 100, fiber: 0, sugar: 0, sodium: 0),
        food("Honey", [], serving: "1 tbsp (21 g)", grams: 21, kcal: 304, p: 0.3, c: 82.4, f: 0, fiber: 0.2, sugar: 82.1, sodium: 4),
        food("Maple syrup", ["syrup"], serving: "1 tbsp (20 g)", grams: 20, kcal: 260, p: 0, c: 67.0, f: 0.1, fiber: 0, sugar: 60.4, sodium: 12),
        food("Sugar", ["white sugar", "granulated sugar"], serving: "1 tsp (4 g)", grams: 4, kcal: 387, p: 0, c: 100, f: 0, fiber: 0, sugar: 99.8, sodium: 1),
        food("Dark chocolate, 70–85%", ["chocolate"], serving: "1 oz (28 g)", grams: 28, kcal: 598, p: 7.8, c: 45.9, f: 42.6, fiber: 10.9, sugar: 24.0, sodium: 20),
        food("Mayonnaise", ["mayo"], serving: "1 tbsp (14 g)", grams: 14, kcal: 680, p: 1.0, c: 0.6, f: 74.9, fiber: 0, sugar: 0.6, sodium: 635),
        food("Ketchup", ["catsup"], serving: "1 tbsp (17 g)", grams: 17, kcal: 101, p: 1.0, c: 27.4, f: 0.1, fiber: 0.3, sugar: 21.3, sodium: 907),
        food("Soy sauce", [], serving: "1 tbsp (16 g)", grams: 16, kcal: 53, p: 8.1, c: 4.9, f: 0.6, fiber: 0.8, sugar: 0.4, sodium: 5493),
        food("Orange juice", ["juice"], serving: "1 cup (248 g)", grams: 248, kcal: 45, p: 0.7, c: 10.4, f: 0.2, fiber: 0.2, sugar: 8.4, sodium: 1),
        food("Apple juice", ["juice"], serving: "1 cup (248 g)", grams: 248, kcal: 46, p: 0.1, c: 11.3, f: 0.1, fiber: 0.2, sugar: 9.6, sodium: 4),
        food("Coffee, black", ["espresso"], serving: "1 cup (240 g)", grams: 240, kcal: 1, p: 0.1, c: 0, f: 0, fiber: 0, sugar: 0, sodium: 2),
        food("Beer", ["lager", "ale"], serving: "12 fl oz (356 g)", grams: 356, kcal: 43, p: 0.5, c: 3.6, f: 0, fiber: 0, sugar: 0, sodium: 4),
        food("Wine, red", ["wine"], serving: "5 fl oz (147 g)", grams: 147, kcal: 85, p: 0.1, c: 2.6, f: 0, fiber: 0, sugar: 0.6, sodium: 4),
        food("Wine, white", ["wine"], serving: "5 fl oz (147 g)", grams: 147, kcal: 82, p: 0.1, c: 2.6, f: 0, fiber: 0, sugar: 1.0, sodium: 5)
    ]
}

// MARK: - Shared text helpers

enum SearchText {
    /// Lowercased, diacritic-free, trimmed.
    static func folded(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Folded words (letters and digits only), in order.
    static func tokens(_ string: String) -> [String] {
        folded(string)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
