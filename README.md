# MealOrbit

MealOrbit is a personal, offline-first calorie and macro log for people who plan meals across a two-week window. Search or scan packaged food via Open Food Facts, lock a portion into an orbit window (Apogee, Zenith, Perigee, Drift), and keep every write on the device. There is no account, no ads, no analytics, and no launch gate.

It is a food log, not medical advice. Nutrition data is credited to Open Food Facts.

## Architecture

Onion Architecture, organised as concentric rings:

- **Domain Model** — pure entities and ports (`OrbitPayload`, `ApogeeEntry`, vault protocols)
- **Domain Services** — portion maths, barcode normalisation, 14-day relocation (`TelemetryService`, `HorizonTransferService`)
- **Application Services** — orchestration (`OrbitSession`)
- **Infrastructure** — SwiftData vault, Open Food Facts client, UIKit split shell hosting SwiftUI

Dependencies point inward. Outer rings are injected as protocol conformances defined in the inner rings. The product is a long-lived local catalogue plus a planning horizon; a strict onion keeps persistence, networking and UI from leaking into the maths that decide grams, day keys and Drift remaps.

The UI is a UIKit shell (`OrbitAppDelegate`, `OrbitSceneDelegate`, `UISplitViewController`) with leaf screens in `UIHostingController`. Compact width collapses the split to a stack. Detail and Assign replace each other in the detail column. The fourteen-day horizon takes the full width.

## Unique feature

A **14-day planning horizon with drag and drop**. Planned payloads can be dragged between days and windows. Each day shows projected kcal against the daily target. Drift (snack) remaps to Perigee when dropped on a future day. When a planned day arrives, converting to eaten is one action. This is the reason to pick MealOrbit: two weeks of orbits, not only today.

Horizon length is 14 days from today, stored as individual `ApogeeEntry` rows keyed by `yyyy-MM-dd`.

## Art style

Low-poly 3D space render. Base prompt reused and extended for every asset:

```
low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting
```

Exact prompt used for each `mlo_` image set:

| Asset | Prompt |
| --- | --- |
| `mlo_AppIcon` | low poly 3d render, faceted geometry, deep space navy with cyan and magenta rim light, orbital station, clean studio lighting, the app's single emblem, a faceted icosahedron satellite with a thin orbital ring, centred, filling the canvas edge to edge, no text, no letters, no words, no rounded corner mask, no drop shadow, opaque background, square composition |
| `mlo_Splash` | … a vertical hero composition with a calm, uncluttered centre band, faceted planet at the bottom, orbital station near the top, dark quiet empty middle third for a wordmark, no text |
| `mlo_Onboarding1` | … a low-poly astronaut examining a faceted grocery crate floating in a station bay, discovering what is in packaged food, no text |
| `mlo_Onboarding2` | … a scanning or measuring motif showing a faceted product canister being identified by a cyan scanning beam from a handheld scanner, no text |
| `mlo_Onboarding3` | … a goal or target motif showing daily progress being met, concentric faceted target rings with a glowing cyan orbit completing around a station core, no text |
| `mlo_EmptyLog` | … an empty faceted vessel or bowl floating in a calm station alcove, waiting to be filled, inviting not sad, no text |
| `mlo_EmptySearch` | … a faceted radar dish or search antenna that has come back with nothing found, empty signal, no text |
| `mlo_EmptyPlan` | … an empty schedule grid or horizon of vacant orbital slots with nothing scheduled, no text |
| `mlo_EmptyWish` | … an empty faceted cargo basket or shopping crate on a station shelf, nothing inside, no text |
| `mlo_SlotApogee` | … a morning motif, faceted rising sun over a planet horizon, simple bold emblem readable at 24 pixels, no text |
| `mlo_SlotZenith` | … a midday motif, faceted sun at zenith with short rays, simple bold emblem readable at 24 pixels, no text |
| `mlo_SlotPerigee` | … an evening motif, faceted crescent moon over a dark planet, simple bold emblem readable at 24 pixels, no text |
| `mlo_SlotDrift` | … a small extra in-between motif, tiny faceted comet or asteroid with a short magenta tail, simple bold emblem readable at 24 pixels, no text |
| `mlo_MacroProtein` | … a symbol standing for protein, a single clear faceted hexagonal crystal cluster emblem, bold silhouette readable at 24 pixels, no text |
| `mlo_MacroCarbs` | … a symbol standing for carbohydrate, a single clear faceted chain of linked cubes emblem, bold silhouette readable at 24 pixels, no text |
| `mlo_MacroFat` | … a symbol standing for dietary fat, a single clear faceted droplet or oil sphere emblem, bold silhouette readable at 24 pixels, no text |
| `mlo_ProductPlaceholder` | … a generic packaged grocery item, faceted unlabeled carton or can, no readable branding, no text, no letters |
| `mlo_CardBackdrop` | … an abstract backdrop suitable for sitting behind a product card, low contrast dark station bay, soft cyan and magenta rim, no text, no bright center, no letters |
| `mlo_Texture` | … a seamless repeating surface pattern of faceted hull panels, even density edge to edge, no focal subject, no text, tileable |
| `mlo_ControlFace` | … the face of a single physical control, a faceted circular dial or knob with cyan tick marks, no text |
| `mlo_ScanOverlay` | … a framing reticle or targeting bracket, four corner brackets only, completely empty open black center, no object in the middle, no text |
| `mlo_TwistHero` | … an emblem representing a fourteen-day planning horizon with drag and drop, faceted orbital rings as a two-week calendar, no text |
| `mlo_SuccessMark` | … a confirmation mark or celebratory emblem, faceted cyan check burst or starburst, no text |
| `mlo_HeaderDecor` | … a wide decorative band, long orbital ring spanning a station horizon, no text |

Each line above is prefixed with the base prompt. `mlo_ScanOverlay` has a punched transparent centre. `mlo_AppIcon` is 1024×1024 with no alpha channel.

## How this app differs

From the 21AUG reference (ByteBite) and the rest of the batch:

- Onion rings instead of MVI / other assigned architectures
- UIKit split shell + SwiftUI leaves, not a SwiftUI card stack
- Space lexicon (Command Deck, Apogee / Zenith / Perigee / Drift, Payload Dossier)
- SwiftData with a versioned schema from day one
- Vendored KeychainAccess for an optional local passcode
- SF Mono telemetry figures, space-orbital palette (`#05080F` / `#22D3EE` / `#E879F9`)
- VisionKit `DataScannerViewController` with a telemetry overlay of codes in frame
- Day keys as `yyyy-MM-dd` strings
- Functional twist is the 14-day drag-and-drop horizon, not gamification
- No Alamofire launch gate, no WebView, no OneSignal, no AppsFlyer

## Build

```bash
cd App12_MealOrbit
xcodegen generate
xcodebuild -scheme MealOrbit -destination 'generic/platform=iOS' build
xcodebuild -scheme MealOrbit -destination 'platform=iOS Simulator,name=iPhone 16' test
```

iOS 17.0+, iPhone portrait, Swift 6.2, `SWIFT_STRICT_CONCURRENCY = complete`.

Bundle ID: `com.mealorbit.orbit`  
User-Agent: `MealOrbit/1.0 (iOS; +https://mealorbit.pro)`  
Contact: https://mealorbit.pro/contact-us
