# MealOrbit — Build Specification

> Batch 21AUG, app 12 of 30. This document is the complete brief for
> building this application. Read all of it before writing any code. Anything
> not specified here is your decision, but must stay consistent with section 3.

**One-line positioning:** Plan two weeks ahead.

| Field | Value |
| --- | --- |
| Product name | MealOrbit |
| Bundle identifier | `com.mealorbit.orbit` |
| Domain | https://mealorbit.pro |
| Contact URL | https://mealorbit.pro/contact-us |
| Deployment target | iOS 17.0 |
| Swift version | 6.2, strict concurrency `complete` |
| Devices | iPhone only, portrait |
| Interface style | Dark |
| Asset prefix | `mlo_` |
| User-Agent | `MealOrbit/1.0 (iOS; +https://mealorbit.pro)` |

---

## 1. Non-negotiable constraints

1. **No CocoaPods.** Dependencies come from Swift Package Manager, a local
   in-repo package, a vendored source folder, or nothing at all — per section 3.
2. **No shared code with the other 29 apps.** Business rules are re-implemented
   here under this app's own type names. Copying files between apps fails review.
3. **All code, identifiers, comments, UI copy and the README are in English.**
4. **No launch gate, no WebView shell, no remote configuration, no analytics.**
5. **No CI files.** No `bitrise.yml`, no `Scripts/`, no `metadata/` folder.
6. **Assets are AI-generated.** No stock photography. SF Symbols may support
   small affordances but must never be the primary iconography — see section 12.
7. **The app must build clean** with
   `xcodegen generate && xcodebuild -scheme MealOrbit -destination 'generic/platform=iOS' build`.
8. **Nothing may echo another app in this batch** in naming, layout or visuals.

---

## 2. Product core (identical behaviour in all 30 apps)

The product is an offline calorie and macro tracker built on Open Food Facts.
No account, no sign-in, no ads, no in-app purchase, no analytics SDK, no remote
config. All user data stays on the device.

### 2.1 User flow

1. Onboarding, 3 to 4 screens, shown once. Ends by writing initial targets.
2. Today screen: energy for the day plus protein / carbs / fat against targets.
3. From Today the user reaches Search (by name) or Scan (barcode).
4. Search or Scan resolves to Detail: per-100 g macros plus a grams field.
5. Detail leads to Assign: pick a slot and either eaten-today or a future date.
6. Assign returns to Today (if eaten) or to Plan (if dated ahead).
7. Today also opens the Log (eaten list), Wish list, and Goals (edit targets).
8. Log rows can be deleted. Targets can be edited. Everything works offline
   except the first fetch of a product that is not already cached.

### 2.2 Open Food Facts contract

Search endpoint:

```
GET https://world.openfoodfacts.org/cgi/search.pl
    ?search_terms=<query>
    &search_simple=1
    &action=process
    &json=1
    &page_size=<app choice, 20 to 40>
```

Product endpoint:

```
GET https://world.openfoodfacts.org/api/v2/product/<code>.json
```

Field rules:

- Read `product_name`, falling back to `generic_name`, then `brands`.
- Read `nutriments.energy-kcal_100g` first.
- If missing, use `nutriments.energy_100g` (kJ) and convert.
- Read `nutriments.proteins_100g`, `carbohydrates_100g`, `fat_100g`.
- A missing macro is `nil`, never silently `0`.
- Cache every successfully resolved product locally, keyed by barcode.

### 2.3 Portion maths

```
kcal100 = energy-kcal_100g ?? (energy_100g / 4.184)

kcal    = kcal100    * grams / 100
protein = protein100 * grams / 100
carbs   = carbs100   * grams / 100
fat     = fat100     * grams / 100
```

Round only at the point of display, never in stored values.

### 2.4 Barcode normalisation

- Accept input from the camera, from a typed field, and from a pasted URL.
- Extract runs of consecutive digits from the raw string.
- Keep a run whose length is between 8 and 14 inclusive.
- If the kept run is exactly 12 digits (UPC-A), prefix it with `0`.
- Use the normalised code for the product endpoint.
- Support EAN-8, EAN-13, UPC-A, UPC-E and QR codes carrying any of the above.

### 2.5 The four slots

| Role | Can be planned ahead | Can be eaten |
| --- | --- | --- |
| Morning meal | yes | yes |
| Midday meal | yes | yes |
| Evening meal | yes | yes |
| Snack | no | yes |

### 2.6 Targets

Daily targets: energy in kcal, protein in g, carbs in g, fat in g. Editable at
any time. Onboarding must produce a sensible first set; do not ship zeros.

### 2.7 Wish list

Products the user intends to buy. No duplicate barcodes. An item can be
promoted straight into a log entry or a plan entry.

### 2.8 States that must be designed

Each of these needs a real screen, not a default:

- No network while resolving an uncached barcode.
- Barcode not present in Open Food Facts.
- Product found but missing energy data.
- Camera permission denied, or restricted by parental controls.
- Search returned zero results.
- Search failed with a transport error.
- Log, plan and wish list each empty.
- First launch, before onboarding has been completed.


---

## 3. Uniqueness assignment for MealOrbit

Each row is unique to this app across all 30. Deviating breaks batch acceptance.

| Axis | Assigned value |
| --- | --- |
| Architecture | **Onion Architecture** |
| UI approach | **UIKit shell hosting SwiftUI via UIHostingController** |
| Naming convention | **Space lexicon** |
| File organization | **Onion rings** |
| Dependency strategy | **Vendored source — `KeychainAccess` copied into Vendor/** |
| Design direction | **Space orbital** |
| Typography | **SF Mono** |
| Navigation pattern | **Split view (NavigationSplitView / UISplitViewController)** |
| AI art style | **Low-poly 3D space render** |
| Functional twist | **14-day planning horizon with drag and drop** |
| Persistence | **SwiftData** |
| Screen composition | see 3.6 |
| Scanner technology | **VisionKit DataScannerViewController** |
| Search endpoint | **/cgi/search.pl, page_size 24** |
| Day key representation | **String in yyyy-MM-dd form** |

### 3.1 Architecture contract

Concentric rings: Domain Model (innermost, pure entities + value objects),
Domain Services, Application Services (use case orchestration), Infrastructure
(outermost: UI, persistence, network). Dependencies point inward only; outer
rings are injected as protocol conformances defined in inner rings.

Put a short comment block at the top of each principal type stating the role it
plays in this architecture. The README must justify the pattern for this product.

### 3.2 UI contract

The app is a UIKit application (AppDelegate + SceneDelegate + UIKit container
controllers) whose screen content is SwiftUI embedded in
`UIHostingController`. Navigation chrome, transitions and the tab container are
UIKit; leaf content is SwiftUI.

### 3.3 Naming contract

Convention: Space lexicon.

Examples to follow: `OrbitPlan`, `ApogeeEntry`, `PayloadMass`, `TelemetryService`, `TransferWindow`

Apply it to types, files, properties, methods and asset names alike.

### 3.4 Dependency contract

Vendored KeychainAccess source used to store the (optional) local passcode. Keep the license file.

### 3.5 Navigation contract

Two-column split: sidebar of orbits/sections, detail pane for content. Collapses to a stack on compact width.

### 3.6 Screen composition contract

The reference batch shipped five apps with an identical screen inventory, which
made them feel like the same product reskinned. This app must not have the same
physical screen structure as any other in the batch.

Sidebar of sections with a detail column. Detail and Assign both render in the
detail column, replacing each other. The fourteen-day horizon grid takes over
the full width when opened.

Section 5 lists the logical functions that must exist. This section decides how
they are grouped into actual screens. Where the two disagree, this section wins.

### 3.7 Scanner contract

Technology: **VisionKit DataScannerViewController**

Telemetry-style overlay listing every code currently in frame.

Do not substitute a different capture technology. The scan screen's composition
and feedback must be recognisably this app's own.

### 3.8 Data representation contract

- Open Food Facts search uses **/cgi/search.pl, page_size 24**.
- A day is represented internally as **String in yyyy-MM-dd form**. Use this consistently in
  storage, in queries and in identifiers.
- The demo seed flag key is `mlo.demo.v1`.
- `NSCameraUsageDescription` is exactly: "MealOrbit reads barcodes to lock a product into an orbit window."

---

## 4. Target file organization

Scheme: **Onion rings**

```
MealOrbit/
  DomainModel/ DomainServices/ ApplicationServices/ Infrastructure/UI/ Infrastructure/Persistence/ Infrastructure/Network/
  Assets.xcassets/
```

Adapt the leaf files to the architecture, but the top-level shape is fixed. Do
not create a `Utils/` or `Helpers/` dumping ground.

---

## 5. Screens

Build all of the following. Screen names must follow this app's naming
convention rather than the generic labels used here.

### 5.1 Onboarding
Three to four pages. Explains the product, collects the initial targets, writes
them, and sets a completion flag. Re-runnable from Goals for testing.
Accepts: a skip path that still writes sensible default targets.

### 5.2 Today
The primary screen. Energy consumed against target, plus protein, carbs and fat
against theirs. The four slots with what has been eaten in each. Entry points to
Search, Scan and the twist feature. Must render correctly when the day is empty,
when the target is exceeded, and when a macro target is unset.

### 5.3 Search
Debounced text query against Open Food Facts. Cancels the previous request.
States: idle, loading, results, empty, transport error. Results show name, brand
and kcal/100 g. Selecting a result opens Detail.

### 5.4 Scan
Live camera barcode capture via AVFoundation. Handles not-determined, denied and
restricted permission states, each with a route to Settings. A manual-entry field
is mandatory so the app is fully usable on the Simulator. Stop the capture
session when the view disappears and when the app backgrounds.

### 5.5 Detail
Per-100 g macros for the resolved product, a grams input, and live-computed
totals. Unknown macros display as unknown, never zero. Actions: assign, or add
to the wish list. Guard against zero, negative and absurd gram values.

### 5.6 Assign
Choose a slot — Apogee, Zenith, Perigee, Drift — and choose
eaten-today or a future date. Drift is eaten-only and must be unavailable
when a future date is selected. Confirm returns to the right destination.

### 5.7 Log
Everything eaten on the selected day, grouped by slot, with per-slot subtotals.
Delete with confirmation. Day switching without leaving the screen.

### 5.8 Plan
Future-dated entries. The horizon and its presentation are this app's choice;
state the horizon in the README. Converting a planned item to eaten is one action.

### 5.9 Wish
Products the user wants to buy. Barcode-unique — adding a duplicate updates the
existing row rather than inserting. Promote to log or to plan.

### 5.10 Goals
Edit the four daily targets, with validation. Also hosts: re-run onboarding,
reset all data (confirmed), and the contact link to
https://mealorbit.pro/contact-us.

### 5.11 Twist screen
See section 11. The twist needs at least one screen of its own plus a surface on
Today.

---

## 6. Domain model

Minimum entities, named per this app's convention:

- **Product** — barcode, name, brand, kcal/100 g, protein/carbs/fat per 100 g
  (each optional), last refresh timestamp.
- **Entry** — id, product reference, grams, slot, date, eaten-or-planned flag.
- **Targets** — kcal, protein, carbs, fat.
- **WishItem** — product reference, added date.
- Plus whatever the twist in section 11 requires.

Day totals, remaining budget and macro percentages are computed, never stored.

---

## 7. Design system

Direction: **Space orbital**

### 7.1 Palette

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#05080F` | Screen background |
| `surface` | `#0E1526` | Cards, rows, sheets |
| `ink` | `#E6F1FF` | Primary text and icons |
| `accent` | `#22D3EE` | Primary action, key figure, progress fill |
| `muted` | `#E879F9` | Secondary text, dividers, disabled |

Define these as named colours in `Assets.xcassets` and reach them through one
typed accessor. Never hard-code a hex string anywhere else.

### 7.2 Typography

Family: **SF Mono**

`.system(.body, design: .monospaced)` for telemetry figures, SF Pro for prose.

Define a type scale of at most six steps behind one accessor and use only those
steps. Text stays legible at the largest Dynamic Type size.

### 7.3 Layout

- One base spacing unit (4 or 8 pt); only multiples of it.
- One corner radius value applied consistently, or deliberately none if the
  design direction calls for hard edges.
- Every interactive element is at least 44x44 pt.

---

## 8. UI and UX quality bar

Every item here is a defect if it is missing. Do not treat this as advice.

**Layout**

- Respect safe areas on every screen. Nothing sits under the notch, the Dynamic
  Island or the home indicator.
- The app is portrait-only on iPhone. Lock it in the Info settings and do not
  write rotation-dependent layout.
- No layout shift when asynchronous data arrives. Reserve the final size up
  front, or use a redacted placeholder of the same dimensions.
- Long product names must truncate gracefully, never push a number off screen.
  Numbers win; names truncate.
- Minimum tap target 44x44 pt for every interactive element, including small
  icon buttons and list accessories.
- Pick one base spacing unit and use only multiples of it. No arbitrary values.

**Keyboard**

- The grams field uses `.decimalPad`, and the decimal separator matches the
  user's locale.
- Content scrolls out from under the keyboard. The focused field is always
  visible.
- Tapping outside the field, or scrolling, dismisses the keyboard.
- Validate on the fly: reject negative and non-numeric input rather than
  crashing the parser later.

**Loading and state**

- Every asynchronous operation has a visible loading state.
- Guard against the spinner flash: if the work finishes in under 150 ms, do not
  show a spinner at all.
- Every list has a designed empty state containing a primary action, not just a
  sentence of text.
- Every error state offers a retry, and states plainly what failed.
- Disable the primary button while its action is in flight so it cannot be
  double-tapped into a double push or a duplicate entry.

**Typography and accessibility**

- All text scales with Dynamic Type. Verify at the largest accessibility size:
  nothing may clip or overlap.
- Every icon-only control has an `accessibilityLabel`. Decorative images are
  marked as decorative so VoiceOver skips them.
- Colour is never the only signal. Pair it with a label, a shape or an icon.
- Honour Reduce Motion: replace movement-heavy transitions with a fade.
- Meet contrast requirements against the palette in section 7. Check the muted
  colour against the background specifically; that is where these palettes fail.

**Formatting**

- Format every number with `NumberFormatter`, never string interpolation. Group
  separators and decimal separators must follow the locale.
- Energy is shown as a whole number of kcal. Macros are shown with at most one
  decimal place.
- Round only at the point of display. Stored values keep full precision.
- Day boundaries use `Calendar.current.startOfDay(for:)` in the user's current
  time zone. Handle the day changing while the app is open, and handle the
  short and long days that daylight saving produces.
- Unknown macro values render as a dash or the word "unknown", never as 0.

**Motion and feedback**

- One haptic on a successful commit (a food logged, a target saved). No haptic
  on navigation.
- Animations are short (0.2 to 0.35 s) and use a single shared easing curve.
- Nothing animates on first appearance of a screen except an intentional entry
  transition.

**Navigation**

- Back always works and never loses entered data without asking.
- A destructive action (delete a log row, reset all data) is confirmed.
- Modal sheets can always be dismissed; there is no dead end.
- Deep state is restorable: relaunching returns the user to a sane screen.


---

## 9. Concurrency

The target builds with Swift 6.2 and `SWIFT_STRICT_CONCURRENCY = complete`. It
must compile with **zero concurrency warnings**. Warnings here become crashes
later, so they are not negotiable.

- All UI types are `@MainActor`. Annotate the type, not individual methods.
- Any value crossing an actor boundary is `Sendable`. Prefer immutable structs
  of primitives.
- Do not use `@unchecked Sendable`. If it is genuinely unavoidable, it needs a
  comment explaining what guarantees the safety.
- No mutable global state. No `static var` that is written after launch.
- Networking and storage APIs are `async` and honour cancellation. When the
  search query changes, cancel the in-flight task; do not let a stale response
  overwrite fresh results.
- Use structured concurrency. Avoid `Task.detached` unless there is a stated
  reason. Never fire a `Task` that outlives the view without owning it.
- Never use `DispatchQueue.main.asyncAfter` to paper over an ordering problem.
  Fix the ordering.
- `Timer` and notification observers are invalidated in `deinit` or on
  disappear.


---

## 10. Persistence engineering

Chosen technology: **SwiftData**

`@Model` OrbitEntry, TransferWindow, MassTarget, WishChip. Repository protocols live in the Domain ring.

This app uses **SwiftData**. SwiftData has several sharp edges that produce
runtime crashes and silent data loss; all of the following are mandatory.

**Container**

- Exactly one `ModelContainer`, created once at app start and injected. Never
  construct a container inside a view body or a computed property.
- Declare an explicit `Schema` listing every `@Model` type.
- Define a `VersionedSchema` and a `SchemaMigrationPlan` from version 1, even
  though there is nothing to migrate yet. Retrofitting migration later is the
  single most expensive SwiftData mistake.
- Handle container creation failure with a recoverable path, not `try!`.

**Modelling**

- Every relationship must declare its inverse with `@Relationship(inverse:)`.
  A missing inverse is the most common SwiftData bug: it produces duplicated
  objects and orphaned rows that only appear after a relaunch.
- Every to-many relationship must declare a delete rule, normally
  `@Relationship(deleteRule: .cascade)` for owned children.
- Use `@Attribute(.unique)` on the product barcode. Understand that this makes
  inserts behave as upserts.
- Do not store derived values (day totals, remaining budget). Compute them.
- Store the day as a normalised `startOfDay` value if you query by day, and
  index it. Querying by a raw timestamp will silently miss rows.

**Threading**

- `ModelContext` is not `Sendable`. Never capture one in a `Task` that hops
  actors.
- Background work uses `@ModelActor`. Inside it, fetch by `PersistentIdentifier`
  rather than passing model objects across the boundary.
- Models themselves are not `Sendable`. Map to plain structs before handing data
  to the UI layer or across an actor boundary.

**Queries**

- `@Query` belongs in views only, with an explicit and stable `sort:`.
- `#Predicate` supports a restricted subset of Swift. Keep predicates to simple
  comparisons on stored properties; do the rest in memory. Calling an arbitrary
  Swift function inside a predicate compiles but traps at runtime.
- Do not build a predicate that captures a non-`Sendable` value.

**Saving**

- Call `context.save()` explicitly after a batch of mutations rather than
  relying on autosave, so the moment of persistence is deterministic.
- Delete through the context, then save, then let the UI update from the query.

**Testing**

- Tests use `ModelConfiguration(isStoredInMemoryOnly: true)`.


Regardless of technology:

- One seam between domain logic and storage; the UI never touches storage types.
- Writes survive a force-quit. Do not rely on `applicationWillTerminate`.
- Deleting a log row is immediately durable.
- Provide `resetAllData()`, used by tests and reachable from Goals.

---

## 11. Networking

- One client type owns both Open Food Facts endpoints.
- Set `User-Agent` on every request. Open Food Facts throttles clients that do
  not identify themselves.
- 15 second timeout. One retry on a transient transport failure, then a typed
  error. Do not retry a 404.
- Cancel the in-flight search when the query changes. Debounce input by roughly
  300 ms.
- Decode into DTO types that mirror the JSON exactly, then map to domain types.
  Never decode straight into your domain model.
- Open Food Facts data is user-contributed and frequently incomplete. Every
  numeric field is optional. A product with no energy value is a normal case
  that the UI must present, not an error.
- Some numeric fields arrive as strings. The decoder must accept both a number
  and a numeric string for every nutriment.
- `status` of `0` in the product response means not found. Map it to a distinct
  error case so the UI can offer manual entry.
- Never crash on malformed JSON. A decoding failure is a handled error.
- Cache every resolved product locally on success, so the app degrades to a
  working offline catalogue.


Set `User-Agent: MealOrbit/1.0 (iOS; +https://mealorbit.pro)` on every request. Never reuse another app's string.
Use the **/cgi/search.pl, page_size 24** search endpoint for this app.

---

## 11a. Patterns proven in the reference batch

The five reference apps in the 18AUG batch were shipped and then hand-polished.
The behaviours below are the ones that survived that polish. Reproduce every one
of them, implemented from scratch under this app's own naming and structure.

**Catalog resilience**

- Keep a bundled local shelf (section 14). When an Open Food Facts search returns
  zero rows, or fails, fall back to matching against the local shelf instead of
  showing an empty screen. A search must never dead-end.
- Merge remote results with local shelf matches and de-duplicate by barcode.
- When resolving a scanned code, generate every plausible candidate (see 2.4) and
  try them in order. Only report a miss after all candidates fail.
- Drop any result whose product name is empty; it is unusable in a list.

**Scanner resilience**

- Detect whether a capture device exists at all. On the Simulator there is none,
  so the scan screen must degrade to sample barcode chips plus manual entry, and
  still be fully functional.
- Debounce repeated reads. After a successful decode, ignore further reads for
  roughly 1.5 to 2 seconds, otherwise one barcode fires a burst of lookups.
- Guard against re-firing on the same payload.
- Start the session when the view appears and stop it when it disappears or the
  app backgrounds. A running session in the background drains battery and trips
  review.

**Slot rules**

- The snack slot cannot be planned ahead. When a user picks a future date, remap
  the snack slot to **Evening** rather than rejecting the action
  outright. The reference apps all do this remap and it avoids a dead end.

**Wish list**

- De-duplicate by barcode. If an item is already wished, show the button in a
  disabled 'already saved' state rather than silently inserting a duplicate.

**Product imagery**

- Three-tier fallback for every product thumbnail: remote image URL, then a
  bundled asset if the product came from the local shelf, then the generic
  placeholder. Never show a blank box.

**Demo data**

- Seed a demo day only under `#if targetEnvironment(simulator)`, guarded by a
  versioned UserDefaults key so it runs exactly once. Never seed on device.

**Onboarding**

- Gate onboarding behind a persisted flag. Completing it writes targets.

**Support**

- The Goals screen carries a link to the contact URL. App Review looks for it.

**Presentation touches that made the reference apps feel finished**

- The main energy number animates when it changes, rather than snapping.
- Lists stagger their appearance slightly instead of all arriving at once.
- A newly added row is briefly highlighted so the user sees where it landed.
- Empty states pair generated art with a headline and one line of explanation.
- Error copy is written in the app's own voice, not as a raw error code.

**Deficiencies in the reference apps — do NOT reproduce these**

The reference batch needed manual fixing in these areas. This app must get them
right the first time:

1. **No haptic feedback anywhere.** This app adds haptics on successful commits.
2. **No accessibility labels anywhere.** This app fully supports VoiceOver.
3. **SQL built by string interpolation.** If this app uses SQLite it must use
   prepared statements with bound parameters.
4. **No caching of resolved products.** This app caches every resolved product so
   it works offline afterwards.
5. **No schema versioning.** This app versions its store from day one.
6. **A denied camera permission silently did nothing.** This app explains the
   state and offers a route to Settings.
7. **Search fired a network request on every keystroke in some apps.** This app
   debounces and cancels the previous request.


---

## 11b. App Store readiness

The app must be submittable without further work.

- `PrivacyInfo.xcprivacy` in the target, declaring the UserDefaults access API
  reason `CA92.1` and the file timestamp reason `C617.1`, with
  `NSPrivacyTracking` false and no collected data types.
- `NSCameraUsageDescription` written specifically for this app. Generic strings
  get rejected.
- `LSApplicationCategoryType` of `public.app-category.healthcare-fitness`.
- Portrait only, iPhone only (`TARGETED_DEVICE_FAMILY = "1"`).
- No account, no sign-in, no delete-account flow, no in-app purchase, no ads, no
  user-generated content, and therefore no report or block UI.
- App Tracking Transparency is never invoked.
- The camera is the only sensitive permission requested.
- The app must not present itself as medical advice. It is a personal food log.
- Nutrition data is credited to Open Food Facts, a public database.


Project settings that follow from the above:

```yaml
INFOPLIST_KEY_UIUserInterfaceStyle: Dark
INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
INFOPLIST_KEY_NSCameraUsageDescription: MealOrbit reads barcodes to lock a product into an orbit window.
INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.healthcare-fitness
TARGETED_DEVICE_FAMILY: "1"
SWIFT_STRICT_CONCURRENCY: complete
```

---

## 12. Functional twist: 14-day planning horizon with drag and drop

A two-week horizon grid where planned foods can be dragged between days and
slots. Each day shows projected kcal against target. Planned items convert to
eaten with one action when the day arrives.

This is the app's marketed differentiator. It must be:

- visible on the Today screen, not buried in settings;
- backed by real persisted data, not a cosmetic flourish;
- covered by at least one unit test;
- described in the README as the reason a user would pick this app.

---

## 13. AI-generated assets

Art style: **Low-poly 3D space render**

Base prompt, reused and extended for every asset:

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting
```

All 24 images below are required. Generate each one, export
as PNG, and add it to `Assets.xcassets` as its own image set named exactly as
given. Every name carries the `mlo_` prefix. No asset may be reused
in any other app in this batch.

### 13.1 App icon rules (strict)

The icon is rejected by App Store Connect if any of these are wrong:

- Exactly **1024 x 1024 px**.
- **No alpha channel.** Not "transparent pixels are unused" — the channel itself
  must be absent. Flatten onto an opaque background before export.
- sRGB colour profile, 8 bits per channel, PNG.
- **No text and no words** in the artwork.
- **No rounded corners and no built-in mask.** iOS applies the mask itself.
- No drop shadow that relies on canvas transparency.
- The subject stays inside the middle 80% so the system mask does not clip it.

Verify before shipping:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha mlo_AppIcon.png
# expected: pixelWidth: 1024, pixelHeight: 1024, hasAlpha: no
```

If `hasAlpha: yes`, strip it:

```bash
sips -s format jpeg mlo_AppIcon.png --out tmp.jpg \
  && sips -s format png tmp.jpg --out mlo_AppIcon.png && rm tmp.jpg
```

### 13.2 Full asset list

| # | Image set | Size (px) | Alpha | Purpose |
| --- | --- | --- | --- | --- |
| 1 | `mlo_AppIcon` | 1024x1024 | **NO** | App Store icon. NO alpha channel, NO transparency, NO text, NO rounded corners, NO drop shadow outside the canvas. |
| 2 | `mlo_Splash` | 1290x2796 | allowed | Launch background. The middle third must stay quiet so the wordmark reads on top. |
| 3 | `mlo_Onboarding1` | 1024x1536 | allowed | Onboarding page 1 illustration: what the app is for. |
| 4 | `mlo_Onboarding2` | 1024x1536 | allowed | Onboarding page 2 illustration: scan and search. |
| 5 | `mlo_Onboarding3` | 1024x1536 | allowed | Onboarding page 3 illustration: setting daily targets. |
| 6 | `mlo_EmptyLog` | 1024x1024 | allowed | Empty state: nothing logged today yet. Calm and inviting, never sad. |
| 7 | `mlo_EmptySearch` | 1024x1024 | allowed | Empty state: search returned no products. |
| 8 | `mlo_EmptyPlan` | 1024x1024 | allowed | Empty state: no planned entries. |
| 9 | `mlo_EmptyWish` | 1024x1024 | allowed | Empty state: wish list has no items. |
| 10 | `mlo_SlotApogee` | 512x512 | allowed | Icon for the 'Apogee' slot. |
| 11 | `mlo_SlotZenith` | 512x512 | allowed | Icon for the 'Zenith' slot. |
| 12 | `mlo_SlotPerigee` | 512x512 | allowed | Icon for the 'Perigee' slot. |
| 13 | `mlo_SlotDrift` | 512x512 | allowed | Icon for the 'Drift' slot. |
| 14 | `mlo_MacroProtein` | 512x512 | allowed | Macro icon: protein. Must be visually distinct from carbs and fat at 24pt. |
| 15 | `mlo_MacroCarbs` | 512x512 | allowed | Macro icon: carbohydrates. |
| 16 | `mlo_MacroFat` | 512x512 | allowed | Macro icon: fat. |
| 17 | `mlo_ProductPlaceholder` | 600x600 | allowed | Fallback thumbnail shown when a product has no image. Used in every list row. |
| 18 | `mlo_CardBackdrop` | 1200x800 | allowed | Backdrop art for the product detail card. Low contrast so text stays readable. |
| 19 | `mlo_Texture` | 2048x2048 | allowed | Tiling background texture used at low opacity behind content. MUST tile with no visible seam. |
| 20 | `mlo_ControlFace` | 512x512 | allowed | Custom control artwork used for the primary interactive element. |
| 21 | `mlo_ScanOverlay` | 1024x1024 | required | Camera overlay art framing the barcode. The centre must be fully transparent. |
| 22 | `mlo_TwistHero` | 1024x1024 | allowed | Hero art for the '14-day planning horizon with drag and drop' feature screen. |
| 23 | `mlo_SuccessMark` | 512x512 | allowed | Shown briefly when a food is logged successfully. |
| 24 | `mlo_HeaderDecor` | 1200x600 | allowed | Decorative header accent on the main screen. |

### Prompt per asset

**`mlo_AppIcon`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, the app's single emblem, centred, filling the canvas edge to edge
```

**`mlo_Splash`** — 1290x2796

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a vertical hero composition with a calm, uncluttered centre band
```

**`mlo_Onboarding1`** — 1024x1536

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a person or object representing discovering what is in packaged food
```

**`mlo_Onboarding2`** — 1024x1536

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a scanning or measuring motif showing a product being identified
```

**`mlo_Onboarding3`** — 1024x1536

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a goal or target motif showing daily progress being met
```

**`mlo_EmptyLog`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an empty vessel, surface or container waiting to be filled
```

**`mlo_EmptySearch`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a search motif that has come back with nothing found
```

**`mlo_EmptyPlan`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an empty schedule, grid or horizon with nothing scheduled
```

**`mlo_EmptyWish`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an empty basket, list or shelf
```

**`mlo_SlotApogee`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a morning motif appropriate to the theme
```

**`mlo_SlotZenith`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a midday motif appropriate to the theme
```

**`mlo_SlotPerigee`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an evening motif appropriate to the theme
```

**`mlo_SlotDrift`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a small extra or in-between motif appropriate to the theme
```

**`mlo_MacroProtein`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a symbol standing for protein, rendered as a single clear emblem
```

**`mlo_MacroCarbs`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a symbol standing for carbohydrate, rendered as a single clear emblem
```

**`mlo_MacroFat`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a symbol standing for dietary fat, rendered as a single clear emblem
```

**`mlo_ProductPlaceholder`** — 600x600

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a generic packaged grocery item with no readable branding
```

**`mlo_CardBackdrop`** — 1200x800

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an abstract backdrop suitable for sitting behind a product card
```

**`mlo_Texture`** — 2048x2048

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a seamless repeating surface pattern
```

**`mlo_ControlFace`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, the face of a single physical control such as a dial, key or slider handle
```

**`mlo_ScanOverlay`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a framing reticle or targeting bracket, open in the middle
```

**`mlo_TwistHero`** — 1024x1024

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, an emblem representing this app's signature feature
```

**`mlo_SuccessMark`** — 512x512

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a confirmation mark or celebratory emblem
```

**`mlo_HeaderDecor`** — 1200x600

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, a wide decorative band or ornament
```


### 13.3 Asset rules

- Assets must be semantically different from each other. Do not generate one
  image and recolour it; each entry has its own subject.
- Slot icons and macro icons must be distinguishable from one another at 24 pt.
  Test them small before accepting them.
- `mlo_Texture` must tile seamlessly. Verify by placing four copies
  edge to edge.
- `mlo_ScanOverlay` needs a genuinely transparent centre.
- Record the exact prompt used for every asset in the README.
- SF Symbols are permitted only for close, chevron, share and similar system
  affordances.

---

## 14. Demo shelf

Seed these six products locally so the app is usable with no network. Adapt the
display names to this app's naming style; keep barcodes and nutrition values
exactly as given.

| Product | Barcode | kcal/100g | Protein | Carbs | Fat |
| --- | --- | --- | --- | --- | --- |
| Eggs | `0072700005005` | 143 | 12.6 | 0.7 | 9.5 |
| Beef Mince 5% | `0208570000000` | 137 | 21.4 | 0.0 | 5.0 |
| Smoked Mackerel | `5000232002501` | 254 | 18.9 | 0.0 | 19.8 |
| Oat Milk | `7394376616037` | 45 | 1.0 | 6.7 | 1.5 |
| Butter | `3178530403022` | 717 | 0.9 | 0.1 | 81.1 |
| Mixed Nuts | `0029000016613` | 607 | 20.0 | 21.0 | 54.0 |

On the Simulator only, optionally seed one demo day of entries so screenshots
are not empty. Never seed on a physical device.

---

## 15. Slot labels

| Role | Label in MealOrbit | Planned | Eaten |
| --- | --- | --- | --- |
| Morning meal | Apogee | yes | yes |
| Midday meal | Zenith | yes | yes |
| Evening meal | Perigee | yes | yes |
| Snack | Drift | no | yes |

---

## 16. Anti-patterns

The following will fail review:

- `try!`, `as!`, or force-unwrapping anything derived from the network, the
  database or a file.
- `fatalError` anywhere reachable at runtime. It is acceptable only for a
  programmer error in an initialiser that cannot fail in practice, and needs a
  comment.
- Swallowing an error with an empty `catch`.
- `print` used as production logging.
- A hard-coded hex colour outside the single colour accessor.
- A hard-coded font name outside the single typography accessor.
- An SF Symbol used as primary iconography.
- Storing a value that can be computed (day totals, remaining budget, macro
  percentages).
- Blocking the main thread on disk or network work.
- `UIScreen.main` for sizing. Use the geometry the layout system gives you.
- Index positions used as list identity. Identity is a stable identifier.
- A view that reaches into the persistence layer directly, bypassing the
  architecture's designated seam.
- Business logic inside a `View` body or a `UIViewController` method, when the
  assigned architecture places it elsewhere.
- Copying a source file from another app in this batch.


---

## 17. Tests

Add a unit test target `MealOrbitTests` covering at minimum:

1. Portion maths, including the kJ fallback path.
2. Barcode normalisation: EAN-8, EAN-13, UPC-A padding, a URL input, and a
   string containing no valid digit run.
3. Missing-macro handling — unknown stays unknown and never becomes zero.
4. Day total aggregation across all four slots.
5. Wish list barcode uniqueness, including the duplicate-add path.
6. Day boundary behaviour across a daylight-saving transition.
7. Decoding a realistic Open Food Facts payload with missing and
   string-encoded nutriment values.
8. The section 12 twist logic.
9. One architecture-specific test proving the pattern holds — a pure reducer or
   update function, an interactor in isolation, or a state machine rejecting an
   illegal transition.
10. A persistence round-trip: write, relaunch-equivalent reload, verify.

---

## 18. README.md

Write `README.md` at the app folder root covering:

1. What the app does and who it is for.
2. The architecture used and **why** it suits this product.
3. The unique feature added and how it works.
4. The AI art style and the exact prompt used for every asset.
5. How this app differs from the reference and from the other apps in the batch.
6. Build instructions.

---

## 19. Definition of done

**Build**
- [ ] `xcodegen generate` succeeds.
- [ ] `xcodebuild -scheme MealOrbit -destination 'generic/platform=iOS' build` succeeds.
- [ ] Zero new compiler warnings.
- [ ] Strict concurrency `complete` compiles clean.
- [ ] Test target passes.

**Function**
- [ ] Onboarding to first logged food works on a clean install.
- [ ] Search, scan and manual barcode entry each resolve a product.
- [ ] All four slots accept entries; Drift rejects future dates.
- [ ] Plan, wish, log deletion and target editing persist across relaunch.
- [ ] Force-quitting immediately after a write loses nothing.
- [ ] Every state in section 2.8 has a designed screen.

**Uniqueness**
- [ ] Architecture matches **Onion Architecture** with no leakage across layers.
- [ ] UI approach matches **UIKit shell hosting SwiftUI via UIHostingController**.
- [ ] Navigation matches **Split view (NavigationSplitView / UISplitViewController)**.
- [ ] Screen composition follows section 3.6, not the generic list in section 5.
- [ ] Scanner uses **VisionKit DataScannerViewController**.
- [ ] Day key is **String in yyyy-MM-dd form**.
- [ ] Typography uses **SF Mono** and nothing else.
- [ ] Palette matches section 7.1 exactly.
- [ ] No source file is shared with another app in the batch.

**Reference parity**
- [ ] Empty or failed search falls back to the local shelf.
- [ ] Remote and local results merge, de-duplicated by barcode.
- [ ] All barcode candidates tried before reporting a miss.
- [ ] Scanner degrades to sample codes plus manual entry with no capture device.
- [ ] Scan reads are debounced and do not re-fire on the same payload.
- [ ] Snack remaps to Evening when a future date is chosen.
- [ ] Wish list shows a disabled 'already saved' state for duplicates.
- [ ] Product thumbnails fall back remote, then bundled, then placeholder.
- [ ] Demo seed runs only on Simulator, once, behind `mlo.demo.v1`.
- [ ] Contact link present on Goals.
- [ ] `PrivacyInfo.xcprivacy` present and correct.
- [ ] Haptics, accessibility, product caching and schema versioning all present
      (the four things the reference batch was missing).

**Assets**
- [ ] All 24 images generated in the **Low-poly 3D space render** style, prefixed `mlo_`.
- [ ] Icon is 1024x1024 with `hasAlpha: no`, verified with `sips`.
- [ ] Texture tiles without a seam; scan overlay centre is transparent.
- [ ] Slot and macro icons are distinguishable at 24 pt.
- [ ] Every prompt recorded in the README.

**Quality**
- [ ] Section 8 UI/UX bar satisfied end to end.
- [ ] Largest Dynamic Type size clips nothing.
- [ ] VoiceOver reaches and correctly labels every control.
- [ ] No item from section 16 present in the codebase.
- [ ] README complete.

---

## 20. Build commands

```bash
cd App12_MealOrbit
xcodegen generate
xcodebuild -scheme MealOrbit -destination 'generic/platform=iOS' build
xcodebuild -scheme MealOrbit -destination 'platform=iOS Simulator,name=iPhone 16' test
```
