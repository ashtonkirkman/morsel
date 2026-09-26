# Morsel — architecture & contributor contract

Minimalist iOS calorie logger. SwiftUI, iOS 17+, SwiftData, Swift 5.9 language mode
(`SWIFT_STRICT_CONCURRENCY=minimal` — do not fight Sendable; `@MainActor` on view models is enough).
Project is generated from `project.yml` with XcodeGen; there is no checked-in `.xcodeproj`.

**No compiler is available in the authoring environment.** Write conservative, well-known SwiftUI/UIKit/
AVFoundation/VisionKit/Swift Charts API only. Prefer APIs that shipped in iOS 16/17 and that you are certain
about. Every type you reference from `Core/` and `DesignSystem/` exists exactly as written there — read those
files before coding. Do not add third-party packages.

## Layout
```
Morsel/App              MorselApp (entry), AppServices (DI wiring), RootView (tabs, + button, add sheet, toast)
Morsel/Core/Models      NutritionFacts, FoodItem, FoodSource, MealType, LogEntry(@Model), FavoriteFood(@Model), MealEstimate
Morsel/Core/Services    ServiceProtocols (BarcodeLookupService, FoodSearchService, MealVisionService, ServiceError),
                        KeychainStore, AppSettings (@Observable, UserDefaults-backed goals/prefs)
Morsel/Core/Nutrition   UserProfile, GoalCalculator (Mifflin-St Jeor), Units
Morsel/Core/Persistence ModelContainer.morsel(), ModelContext+Queries (entries(on:), log(_:), dailyCalories…), PhotoStore/ImageResizer
Morsel/DesignSystem     Theme (Color.m*, Spacing, Radius, MorselFont, Format, Haptics), Components (Card, SectionHeader,
                        EmptyStateView, PrimaryButtonStyle/.morselPrimary, .morselSecondary, Chip, FloatingAddButton,
                        CalorieRing, MacroBar, MacroDot, LoadingOverlay, ConfidenceBadge, FoodRow)
Morsel/Features/<X>     One folder per feature. Views + view models + feature-private services.
MorselTests             XCTest unit tests (pure logic only: parsers, mappers, math). No UI tests.
server/claude-proxy     Cloudflare Worker that holds the Anthropic key.
```

## Environment objects available in every view
```swift
@Environment(AppSettings.self) private var settings     // goals, prefs, endpoint mode
@Environment(AppServices.self) private var services     // .barcode, .search, .vision
@Environment(\.modelContext) private var context        // SwiftData
```
Views under `Features/` must be constructible with the exact signatures below — `RootView` already calls them:

| View | Signature | Owner |
|---|---|---|
| `TodayView` | `TodayView()` | dashboard agent |
| `HistoryView` | `HistoryView()` | dashboard agent |
| `SettingsView` | `SettingsView()` | dashboard agent |
| `OnboardingView` | `OnboardingView()` — sets `settings.hasCompletedOnboarding = true` when done | dashboard agent |
| `SnapMealFlowView` | `SnapMealFlowView(onLogged: @escaping ([LogEntry]) -> Void)` | vision agent |
| `BarcodeScanFlowView` | `BarcodeScanFlowView(onLogged: @escaping ([LogEntry]) -> Void)` | barcode agent |
| `FoodSearchFlowView` | `FoodSearchFlowView(onLogged: @escaping ([LogEntry]) -> Void)` | search agent |
| `QuickAddFlowView` | `QuickAddFlowView(onLogged: @escaping ([LogEntry]) -> Void)` | search agent |

Flow views are presented inside a `.sheet`. They own their own `NavigationStack`, insert entries with
`try context.log(food, quantity:, mealType:, at:, photoFilename:, confidence:)` (or `context.insert` + `save`),
then call `onLogged(entries)`. Cancel = `onLogged([])`. The host dismisses the sheet and shows the toast/undo.

Concrete services `AppServices` expects (exact names/inits):
- `OpenFoodFactsClient()` conforming to **both** `BarcodeLookupService` and `FoodSearchService` (barcode agent).
- `ClaudeVisionService(settings: AppSettings)` conforming to `MealVisionService` (vision agent).

Shared serving editor: the search agent owns `ServingEditorView(food: FoodItem, initialQuantity: Double,
mealType: Binding<MealType>, onConfirm: (FoodItem, Double) -> Void)`; barcode + vision flows may use it or
their own inline controls. Keep it in `Features/Search/ServingEditorView.swift`.

## Design rules
- Background `Color.mBackground`, surfaces via `Card {}`, one accent `Color.mAccent`. No borders, no shadows
  except the floating button/toast. Large rounded numerals (`MorselFont.display/numeral`).
- Minimum taps to log: the happy path must never need more than one confirm tap after capture.
- Every network step shows `LoadingOverlay`, every failure shows an inline, plain-English message with a retry.
- Dark mode must work (all colors are dynamic already). Dynamic Type: use system text styles.
- Accessibility labels on icon-only buttons.

## Claude API (vision agent) — raw HTTPS, no SDK exists for Swift
POST `https://api.anthropic.com/v1/messages` (direct mode) or `settings.proxyURL` + `/v1/messages` (proxy mode).
Headers: `content-type: application/json`, `anthropic-version: 2023-06-01`, and in direct mode `x-api-key: <key>`.
Body:
```json
{ "model": "claude-opus-5", "max_tokens": 4096,
  "system": "<stable system prompt, cache_control on it>",
  "messages": [{ "role": "user", "content": [
      { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "<b64>" } },
      { "type": "text", "text": "<instruction + optional user hint>" } ] }],
  "output_config": { "format": { "type": "json_schema", "schema": { ...additionalProperties:false, required: [...] } } } }
```
Response: `content` is an array of blocks; take the first block with `"type":"text"` and JSON-decode its `text`
into the schema. Check `stop_reason`: `"max_tokens"` → incomplete, `"refusal"` → surface a friendly error.
Structured-output schema rules: no `minimum/maximum/minLength`, every object has `additionalProperties:false` and
`required` listing all properties. Thinking is on by default for this model; do not send a `thinking` field.
Map HTTP 401 → `.unauthorized`, 429 → `.rateLimited`, 5xx → `.server`, URLError → `.network`.
