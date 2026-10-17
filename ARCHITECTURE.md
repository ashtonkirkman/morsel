# Free Track — architecture & contributor contract

Minimalist iOS calorie logger. SwiftUI, iOS 17+, SwiftData, Swift 5.9 language mode
(`SWIFT_STRICT_CONCURRENCY=minimal` — do not fight Sendable; `@MainActor` on view models is enough).
Project is generated from `project.yml` with XcodeGen; there is no checked-in `.xcodeproj`.

**No compiler is available in the authoring environment.** Write conservative, well-known SwiftUI/UIKit/
AVFoundation/VisionKit/Swift Charts API only. Prefer APIs that shipped in iOS 16/17 and that you are certain
about. Every type you reference from `Core/` and `DesignSystem/` exists exactly as written there — read those
files before coding. Do not add third-party packages.

## Layout
```
FreeTrack/App              FreeTrackApp (entry), AppServices (DI wiring), RootView (tabs, + button, add sheet, toast)
FreeTrack/Core/Models      NutritionFacts, FoodItem, FoodSource, MealType, LogEntry(@Model), FavoriteFood(@Model), MealEstimate
FreeTrack/Core/Services    ServiceProtocols (BarcodeLookupService, FoodSearchService, MealVisionService, ServiceError),
                        KeychainStore, AppSettings (@Observable, UserDefaults-backed goals/prefs)
FreeTrack/Core/Nutrition   UserProfile, GoalCalculator (Mifflin-St Jeor), Units
FreeTrack/Core/Account     AccountService (sign-in/out, session), AccountAPIClient, PKCE, AppleSignInCoordinator,
                        WebOAuthFlow (ASWebAuthenticationSession), SyncEngine + SyncCollections (docs/ACCOUNTS.md)
                        UserProfile stores `birthDate` and derives `age` (legacy JSON with an Int `age` still decodes)
FreeTrack/Core/BodyScan    On-device body scanner (docs/BODY_SCAN.md): BodyMeasurementEngine + PoseValidator + BodyScanComparison
                        (pure, unit-tested), BodyKeypoints/BodyMask/BodyMetric/BodyMeasurements, BodyFraming (full body /
                        head to hips / head and shoulders), VisionPoseDetector,
                        BodySegmenter (VisionPersonSegmenter default, SAM2Segmenter + SAM2Model/SAM2ModelStore optional),
                        BodyScanAnalyzer (pipeline), BodyFormat (cm/in, kg/lb), BodyScanPhotoStore (`bodyscan-` JPEGs),
                        ProgressPhotoImporter (EXIF capture date) + ProgressThumbnails (cache)
FreeTrack/Core/Models      BodyScan(@Model) + BodyScanDTO (scalars + measurementsJSON; photos/keypoints never sync),
                        ProgressPhoto(@Model, never synced) + ProgressTimelineItem (imported photos ∪ scan photos)
FreeTrack/Core/Persistence ModelContainer.freeTrack(), ModelContext+Queries (entries(on:), log(_:), dailyCalories…), PhotoStore/ImageResizer,
                        ModelContext+BodyScans (bodyScans(), baselineBodyScan(), saveBodyScan, setBaselineBodyScan, deleteBodyScan,
                        referenceShoulderWidthCm()), ModelContext+ProgressPhotos (progressPhotos(), saveProgressPhotos, deleteProgressPhoto)
FreeTrack/DesignSystem     Theme (Color.m*, Spacing, Radius, FreeTrackFont, Format, Haptics), Components (Card, SectionHeader,
                        EmptyStateView, PrimaryButtonStyle/.freeTrackPrimary, .freeTrackSecondary, Chip, FloatingAddButton,
                        CalorieRing, MacroBar, MacroDot, LoadingOverlay, ConfidenceBadge, FoodRow)
FreeTrack/Features/<X>     One folder per feature. Views + view models + feature-private services.
FreeTrack/Features/Search  FoodSearchFlowView + FoodSearchViewModel, ServingEditorView, BasicFoodCatalog (offline unbranded
                        staples with USDA-style values, shown first), SearchRanking (re-orders Open Food Facts hits so
                        plain English names lead, drops non-Latin names, dedupes)
FreeTrack/Features/Scan    OpenFoodFactsClient (barcode: world.openfoodfacts.org product API; search: search.openfoodfacts.org
                        filtered to English + United States, widened to all English, one retry on 5xx, legacy search.pl
                        fallback) + OpenFoodFactsMapper (accepts both `hits` and `products` shapes)
FreeTrack/Features/Account SignInButtonsView, AccountSettingsSection, AccountPage (onboarding)
FreeTrack/Features/BodyScan BodyView (tab), BodyScanFlowView + BodyScanFlowModel (also `init(importing:)` for a scan from an old
                        photo), BodyPoseCaptureView + BodyCameraController, PoseOverlayView (Canvas skeleton/mask),
                        BodyScanDetailView, BodyScanCompareView, BodyTrendChart, BodyScanSettingsView (SAM 2 toggle/download,
                        self-timer), BodyScanIntroSheet, ProgressPhotosCard (timeline strip), ProgressPhotoImportView
                        (multi-pick + dates/angles), ProgressPhotoCompareView (before/after, slider), ProgressPhotoDetailView
FreeTrackTests             XCTest unit tests (pure logic only: parsers, mappers, math). No UI tests.
server/ai-proxy         Cloudflare Worker that holds the OpenAI key and forwards to the Responses API.
server/account-api      Cloudflare Worker + D1: accounts (Apple/Google/Facebook) and document sync.
```

## Environment objects available in every view
```swift
@Environment(AppSettings.self) private var settings     // goals, prefs, endpoint mode
@Environment(AppServices.self) private var services     // .barcode, .search, .vision, .account, .sync
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
| `BodyView` | `BodyView()` — "Body" tab between History and Settings | body-scan agent |
| `BodyScanFlowView` | `BodyScanFlowView(onSaved: @escaping (BodyScan?) -> Void)` — nil = cancelled; `BodyScanFlowView(importing: ImportedScanPhoto, onSaved:)` | body-scan agent |
| `BodyScanDetailView` / `BodyScanCompareView` | `BodyScanDetailView(scan:)`, `BodyScanCompareView(baseline:current:)` | body-scan agent |

Flow views are presented inside a `.sheet`. They own their own `NavigationStack`, insert entries with
`try context.log(food, quantity:, mealType:, at:, photoFilename:, confidence:)` (or `context.insert` + `save`),
then call `onLogged(entries)`. Cancel = `onLogged([])`. The host dismisses the sheet and shows the toast/undo.

Concrete services `AppServices` expects (exact names/inits):
- `OpenFoodFactsClient()` conforming to **both** `BarcodeLookupService` and `FoodSearchService` (barcode agent).
- `OpenAIVisionService(settings: AppSettings)` conforming to `MealVisionService` (vision agent). `ClaudeVisionService` stays in the tree as an alternative backend and shares the prompt/schema/parsing via `ClaudeVisionCodec`.

Shared serving editor: the search agent owns `ServingEditorView(food: FoodItem, initialQuantity: Double,
mealType: Binding<MealType>, onConfirm: (FoodItem, Double) -> Void)`; barcode + vision flows may use it or
their own inline controls. Keep it in `Features/Search/ServingEditorView.swift`.

## Design rules
- Background `Color.mBackground`, surfaces via `Card {}`, one accent `Color.mAccent`. No borders, no shadows
  except the floating button/toast. Large rounded numerals (`FreeTrackFont.display/numeral`).
- Minimum taps to log: the happy path must never need more than one confirm tap after capture.
- Every network step shows `LoadingOverlay`, every failure shows an inline, plain-English message with a retry.
- Dark mode must work (all colors are dynamic already). Dynamic Type: use system text styles.
- Accessibility labels on icon-only buttons.

## OpenAI API (vision agent) — raw HTTPS, no SDK
POST `https://api.openai.com/v1/responses` (direct mode) or `settings.proxyURL` + `/v1/responses` (proxy mode).
Headers: `content-type: application/json`, and in direct mode `authorization: Bearer <key>`. Proxy mode sends the optional
shared token as `x-morsel-token`.
Body:
```json
{ "model": "gpt-6-luna", "max_output_tokens": 4096, "store": false,
  "instructions": "<stable system prompt>",
  "reasoning": { "effort": "low" },
  "input": [{ "role": "user", "content": [
      { "type": "input_image", "image_url": "data:image/jpeg;base64,<b64>", "detail": "high" },
      { "type": "input_text", "text": "<instruction + optional user hint>" } ] }],
  "text": { "format": { "type": "json_schema", "name": "meal_estimate", "strict": true, "schema": { ...additionalProperties:false, required: [...] } } } }
```
Response: `output` is an array of items; skip `reasoning` items, take the first `message` item, and inside it the first
`output_text` part; JSON-decode its `text` into the schema. A `refusal` part → friendly error. Check `status`:
`"incomplete"` with `incomplete_details.reason == "max_output_tokens"` → incomplete; `"failed"` → surface `error.message`.
Strict-schema rules: no `minimum/maximum/minLength`, every object has `additionalProperties:false` and `required` listing
all properties; nullable fields use `anyOf` with `{"type":"null"}`.
Map HTTP 401 → `.unauthorized`, 429 → `.rateLimited`, 5xx → `.server`, URLError → `.network`.
The prompt, schema and estimate mapping live in `ClaudeVisionCodec` and are reused by `OpenAIVisionCodec`; the Claude
Messages-API envelope is kept there too so the two backends can be A/B tested on the same photo.
