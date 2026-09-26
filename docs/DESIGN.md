# Design

Morsel's design goal is that logging a meal feels lighter than not logging it. One accent colour, warm
neutrals, big numerals, soft cards, and never more than one confirm tap after a capture. This document
is the human-readable side of `Morsel/DesignSystem/Theme.swift` and `Components/`; when they disagree,
the code wins and this file gets updated.

## Visual language

### Colour tokens (`Color.m*`, all dynamic light/dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `mBackground` | `#FAF9F6` warm off-white | `#0F0F10` | Screen background |
| `mSurface` | `#FFFFFF` | `#1B1B1E` | Cards, sheets, toast |
| `mSurfaceElevated` | `#F2F0EB` | `#26262A` | Chips, inset controls |
| `mText` | `#141414` | `#F4F4F2` | Primary text |
| `mTextSecondary` | `#6E6E73` | `#9C9CA3` | Servings, captions |
| `mTextTertiary` | `#A6A6AB` | `#6B6B72` | Placeholders, disabled |
| `mSeparator` | `#E8E6E1` | `#2E2E33` | Hairlines only where a list needs them |
| `mAccent` | `#2F8F5B` calm green | `#4CC38A` | The single brand colour: ring, primary button, links, toast check. Also the app icon background. |
| `mAccentSoft` | `#E4F3EA` | `#173323` | Tinted fills behind accent text/icons |
| `mWarning` | `#D98E1B` | `#F0B14E` | Low-confidence estimates, over-goal |
| `mDanger` | `#D1453B` | `#F07167` | Destructive actions, errors |
| `mProtein` / `mCarbs` / `mFat` | blue `#3B6FD1` / amber `#D98E1B` / plum `#B65AA8` | lighter variants | Macro bars and legend dots; a colour-blind-safe triad |

Rules: no borders, no shadows except the floating add button and the toast. Surfaces are distinguished
from the background by tone alone. Do not introduce a second accent; state is shown with `mWarning` and
`mDanger`, everything else is neutral or green.

### Spacing, radius, type

- **Spacing** (`Spacing`): 4 / 8 / 16 / 24 / 32 / 48. Screen gutters are 16, card padding 16, section
  gaps 24.
- **Radius** (`Radius`): cards 20, controls 14, chips fully round. Always `.continuous` corners.
- **Type** (`MorselFont`): rounded design for anything numeric or heading-like, default design for body
  text. `display` is the 56 pt semibold hero numeral (today's calories); `numeral` is the monospaced
  title3 used in rows so columns of calories align. Everything else uses system text styles so Dynamic
  Type works for free.
- **Formatting** (`Format`): calories are integers ("1,840 kcal"), grams show one decimal under 10 g,
  quantities drop trailing zeros, percentages are integers.
- **Haptics** (`Haptics`): success on log, warning on low confidence, light tap on chip selection. All
  behind `settings.hapticsEnabled`.

### Components (the only building blocks)

| Component | Role |
|---|---|
| `Card` | The one container. Soft 20 pt surface, no border. |
| `SectionHeader` | Small caps-free header with optional trailing action. |
| `EmptyStateView` | Icon + one sentence + one button. Never a blank screen. |
| `PrimaryButtonStyle` (`.morselPrimary`) / `SecondaryButtonStyle` (`.morselSecondary`) | Full-width accent button / tinted secondary. |
| `Chip` | Pill for meal type and serving presets. |
| `FloatingAddButton` | The big "+" over the tab bar; the only element with a shadow besides the toast. |
| `CalorieRing` | Thin progress ring with the hero numeral inside. Green up to the goal, warning past it. The app icon echoes this. |
| `MacroBar`, `MacroDot` | Horizontal macro progress and legend dots. |
| `LoadingOverlay` | Translucent full-screen progress for every network step. |
| `ConfidenceBadge` | Compact high/medium/low tag on every AI estimate. |
| `FoodRow` | Name, serving, calories right-aligned. Used everywhere a food is listed. |

## Interaction principles

1. **Photo first.** The add menu lists Snap a meal before Scan, Search and Quick add because it is the
   lowest-effort path. The camera opens immediately; the library picker is one tap away.
2. **One confirm tap.** After a capture, the happy path is exactly one tap ("Log") to save. The AI may
   ask one clarifying question when it is unsure; answering it and logging is still a single flow.
   Every value is editable, but editing is never required.
3. **Estimates are labelled, not hidden.** AI numbers carry a `ConfidenceBadge` and the word
   "Estimate". Barcode and database values do not.
4. **Undo instead of confirm dialogs.** Logging shows the toast "Logged - 540 kcal" with Undo for four
   seconds. Deleting from a list is a swipe with no alert. Nothing important is ever behind an "Are you
   sure?".
5. **Always a way forward.** Network work shows `LoadingOverlay`; failure shows a plain-English inline
   message with Retry (and, for "not found", an offer to search or quick add instead). Empty lists show
   `EmptyStateView` with the next action.
6. **Quiet by default.** No streaks, badges, notifications or nagging. The ring and the number are the
   whole dashboard.
7. **Accessible without effort.** System text styles, dynamic colours, VoiceOver labels on icon-only
   buttons, 44 pt minimum tap targets, portrait-only on iPhone.

## Screen map

```
RootView (tabs + floating + button + toast)
+-- Onboarding (first launch only)
|     welcome -> body stats (Mifflin-St Jeor) -> goals preview -> AI setup (proxy URL / skip)
+-- Today                      CalorieRing, MacroBars, meals grouped by MealType, swipe to delete
+-- History                    day/week/month Swift Charts, streak-free totals, CSV export
+-- Settings                   goals, units, AI endpoint (proxy/direct + key), haptics, auto-log
|                              high-confidence toggle, About / privacy, diagnostics
+-- [+] Add sheet
      +-- AddMenuView          Snap a meal / Scan barcode / Search / Quick add
      +-- SnapMealFlowView     camera or library -> LoadingOverlay -> review (items, confidence,
      |                        clarifying question) -> Log
      +-- BarcodeScanFlowView  live scanner -> product -> ServingEditorView -> Log
      +-- FoodSearchFlowView   search field, Recents, Favorites -> ServingEditorView -> Log
      +-- QuickAddFlowView     name + kcal (+ optional macros) -> Log
```

Every flow view owns its `NavigationStack`, inserts entries, and calls `onLogged(entries)`; the host
dismisses the sheet and shows the toast. Cancel is `onLogged([])`.

## App icon

Accent green `#2F8F5B` background, white ring (stroke 70 px at 1024) with a gap at 12 o'clock and a
filled dot in the gap: the calorie ring with its "now" marker. No text, no gradient, square corners
(iOS masks it). Regenerate with `make icon` (`scripts/make_icon.py`).
