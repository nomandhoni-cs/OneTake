# SwiftUI View Implementation Guidelines

> **Read this BEFORE implementing any view.** This is the mandatory instruction set for every screen, control, and component built in OneTake. It encodes Apple's Human Interface Guidelines (design principles, iOS platform characteristics), Apple's guidance on first launch and launch performance, and this codebase's own architecture contract ([ARCHITECTURE.md](ARCHITECTURE.md), [AGENTS.md](../AGENTS.md)).
>
> **Entry point:** [`AGENTS.md`](../AGENTS.md) → this doc → [ARCHITECTURE.md](ARCHITECTURE.md) → [CODEMAP.md](CODEMAP.md)

---

## 0. How to Use This Doc

1. **Before writing a single line of view code** — run the Pre-Implementation Gate (§3).
2. **While implementing** — follow the rules in §4–§13. Rules use RFC-style language: **MUST** (hard requirement, enforced by lint/review), **SHOULD** (strong default, deviation needs a written justification in the PR), **MAY** (allowed option).
3. **Before opening a PR** — run the Definition of Done checklist (§18).

Design is making something **with intention**. Every view you add asks the person using it for their time, attention, and trust — these are valuable things you can't afford to waste. Choosing what to build is often deciding what *not* to include.

---

## 1. Design Principles — Apply These to Every View

There's no formula that guarantees a perfect solution. These principles are tools to help you weigh competing priorities. You might find leaning into one feels like compromising another — that's what makes design interesting. Use knowledge and intuition to find the best path.

### 1.1 Purpose — Make something meaningful

- Every view MUST have a one-sentence purpose stated in its header comment ("Owns: …"). If you can't state it, the view doesn't exist yet — think first.
- Ask *what the view is for* at every stage. A view that serves no clear use is dead weight on the person trying to meet a goal.
- Prioritize the app's most important features and make those great. Don't spread effort evenly across everything.
- Before re-creating an existing solution, investigate what exists (native controls, this codebase's `Core/*` kit). Define what sets this app apart and let the design reflect that.

### 1.2 Agency — Let people do things their own way

- **Stay out of the way.** Get people directly to the task or content. The best views are unobtrusive and present when needed.
- **No locked flows.** Never force a pre-determined path. If a guided flow is necessary, make it skippable. People are far more engaged when they control their own experience at their own pace.
- **Offer forgiveness.** People accidentally send, change, and delete things all the time:
  - Undo: destructive actions MUST be reversible — swipe actions with undo, a snackbar/toast with "Undo", or `ConfirmationDialog` before the destructive act.
  - Double-check: when someone is about to do something destructive, confirm it's what they mean (see §11.2).
  - Interruptions (alerts) only when someone is about to make a big mistake — not for every action.
- Forgiveness gives people confidence they can recover from anything, which makes them feel capable, secure, and free to explore.

### 1.3 Responsibility — Act in people's best interest

- **Privacy is a human right.** Don't be the interface equivalent of "give me your phone number — I'll tell you why later." Wait for the right moment to ask for personal data; ask only for what's necessary; be transparent about what it's for (see §16).
- **Keep people safe.** For every feature, ask: *How could this be misused? Who would be harmed? How do I prevent it?* Anticipate failure modes (a model generating something wrong, a recording being lost, a file being corrupted) and put safeguards in place.
- If risks to people outweigh the value, remove the feature entirely.
- Taking responsibility seriously is what leads to a product people trust.

### 1.4 Familiarity — Build on what people know

- **Use metaphors people already know** (trash = delete, folder = group, slider = gradual value). The trick: not too literal (people won't recognize it), not too abstract (the idea won't get across). A good metaphor draws on something people know and lets them predict what it will do.
- **Never repurpose familiar symbols** — a trash can icon MUST mean delete. No creative liberties with the delete icon; people lose immediate recognition.
- **Things that look the same MUST behave the same.** Consistent appearance → consistent behavior. If one button navigates, another toggles, a third pops a modal — there's no pattern to learn.
- **Consistent placement.** The same action lives in the same location across screens (trailing nav slot for primary action, bottom-middle for thumb reach, context menu for row actions). Consistency speeds people up because they don't have to think about it.
- **Provide clear feedback** (see §11.1) — show when controls are available, when content changes, and use system patterns for alerts and choices.

### 1.5 Flexibility — Adapt to diverse contexts and needs

- People use this app in ways as unique as they are. Design for the way people actually hold and use an iPhone (§2), one-handed and two-handed, portrait and landscape.
- **Accessibility is a priority from the start, not a retrofit** (see §8). Design inclusively to reach the broadest audience and create a better experience for everyone.
- **Adapt seamlessly** to appearance changes — Dark Mode, Dynamic Type, Increase Contrast, landscape — letting people choose the configurations that work best for them.
- **Preserve context.** Keep content and controls in consistent, predictable positions; use natural animations to ease transitions. Restore the previous state when the app restarts (scroll position, selected tab, draft text) — never make people retrace steps.
- Support multiple input methods: touch, voice (VoiceControl), keyboard (iPad/macOS-designed), AssistiveTouch.
- When no single design makes everyone happy, let people personalize (rearrange, hide unused controls) — flexibility proves you designed with them in mind.

### 1.6 Simplicity — Be clear and direct

- **Simple ≠ minimal.** Burying functionality in one place looks minimal but isn't simple. Simple designs are frictionless: people find what they need without effort.
- **Be concise.** Plain language, no jargon, speak naturally. Strip redundancy. Respect people's time — reduce steps to get things done.
- **Be clear.** Build hierarchy with order, spacing, and contrast so the most important item is always the most obvious one. The interface must answer: *What do I pay attention to? What can I interact with? How?*
- **Every element earns its place.** Distill information to its essence — complex data might be better as a graphic, details summarized so people focus on what they care about.
- **Sometimes simple means adding context.** A play/pause button that also shows elapsed and remaining time is simpler, not more complex — it lets people make informed decisions.
- You've arrived at simplicity when you have *exactly enough*.

### 1.7 Craft — Care about every detail

- Everyone knows what a rushed interface feels like: tap a button and wait, jittery scrolling, misaligned icons, broken rotation. It feels fragile — and fragile software makes people question the quality of the results.
- **High-quality materials:** system fonts (SF) that scale across devices, semantic colors that adapt to light/dark, clear iconography (SF Symbols at correct weights), responsive animations that give immediate natural feedback — all on reliable SDKs.
- **Iterate.** Prototype early, refine every feature, test in real-world settings. Set a high bar, try again.
- **Maintain.** Shipping isn't the finish line. Keep views current with new platform capabilities (Liquid Glass on iOS 26, new SF Symbols, `ContentUnavailableView`). Design is an ongoing commitment.
- Craft is an uncompromising commitment to detail — when you get details right, people know you care.

### 1.8 Delight — Make it human

- Delight isn't confetti tacked on at the end. Identify the **emotion** the view should inspire (a teleprompter studio: confident and focused; a review screen: calm control) and reinforce it through the design.
- **Create defining moments** — from a button press to an error message, each interaction is a chance to add a touch of character in the app's spirit.
- **Don't mistake delight for decoration.** People are trying to accomplish a task; delight never gets in the way of the core purpose.
- Delight is the *sum* of consideration: agency to act, safety to explore, familiar metaphors, flexibility to make it their own. Get all the principles right and the joy follows naturally.

---

## 2. iOS Platform Characteristics — Design for the Device

People depend on their iPhone to stay connected, play games, view media, accomplish tasks, and track personal data — **in any location, while on the go**. Let these fundamentals shape every decision:

| Characteristic | Implication for your views |
|---|---|
| **Display** — medium-size, high-resolution | Design for ~390–430pt logical width; 44pt controls; generous type. Not a shrunken iPad. |
| **Ergonomics** — held in one or both hands, portrait/landscape, viewed at 1–2 ft | Thumb-reach matters: primary actions in the middle/bottom; destructive/one-off actions away from where thumbs rest. Support rotation if the content benefits (video editing does). |
| **Inputs** — Multi-Touch, virtual keyboards, voice control, gyroscope/accelerometer | Touch-first targets; no hover-only affordances; keyboard avoidance; VoiceOver from day one. |
| **App interactions** — sessions from 1–2 min (check a take) to 1+ hr (record a script) | Support both: instant resume to previous state for short visits; comfortable sustained use (battery, thermal, eye strain) for long ones. |
| **System features** — Widgets, Home Screen quick actions, Spotlight, Shortcuts, Activity views | Where relevant, integrate (Live Activity for recording, AppIntents) in familiar system-consistent ways. |

**iOS best practices you MUST honor:**

- Help people concentrate on primary tasks and content by **limiting onscreen controls**; make secondary details and actions discoverable with minimal interaction (context menus, menus, disclosure).
- **Adapt seamlessly to appearance changes** — orientation, Dark Mode, Dynamic Type — letting people choose what works best for them.
- **Support the way people hold the device.** Easier and more comfortable to reach a control in the middle/bottom; let people swipe to navigate back; put row actions where swipe-to-act works.
- **With permission**, integrate platform info (biometrics, payments, location) to enhance the experience rather than asking people to enter data.

---

## 3. Pre-Implementation Gate — Run BEFORE Writing Code

Answer these in the view's header comment or the PR description. If any answer is "no", stop and rethink.

1. **Purpose:** What is this view for, in one sentence? What matters most to the person using it? What are we *not* building?
2. **Agency:** Can people reach their goal their own way? Can they recover from a mistake (undo/confirm)? Is any flow locked or forced?
3. **Responsibility:** Does this view touch private data or request a permission? Is the timing right (ask when needed, not at launch)? What's the misuse scenario?
4. **Familiarity:** Which existing patterns does this build on (native control, existing OneTake view)? Does anything repurpose a familiar symbol? Are similar things in this app rendered the same way?
5. **Flexibility:** Does it work in Dark Mode, Dynamic Type sizes, landscape (if supported), VoiceOver, 44pt touch, reduced motion? What state must it restore on relaunch?
6. **Simplicity:** Can anything be removed? Is every element earning its place? Is copy in plain language? Can steps be reduced?
7. **Craft:** Are colors semantic, fonts system, symbols correct weight? Does every tap give immediate feedback?
8. **Delight:** What emotion is this view going for? Is delight ever getting in the way of the task?

Then check the code-level gate:

- [ ] The view is a `struct SomeName: View` (small, focused — see §4.1)
- [ ] Data flow direction decided (§13)
- [ ] Semantic colors/typography only (§6, §7)
- [ ] Layout plan respects safe areas + 44pt targets (§5)
- [ ] Accessibility labels/traits planned (§8)
- [ ] State restoration keys chosen (§13.5)

---

## 4. View Architecture & Code Structure

### 4.1 Small, focused views

- **MUST:** Every view is a `struct: View`. **No `func makeSomething() -> some View` helper functions** (SwiftLint `avoid_helper_func_view`). Extract a `struct SmallView: View` instead — it gets its own identity, previews, and modifier scope.
- **SHOULD:** Keep bodies under ~85 lines (SwiftLint `function_body_length` 85 warning / 150 error). When it grows, split into child structs named for what they render (`ScriptRow`, `LUTSwatchView`, `TrimScrubberView`).
- **SHOULD:** One view file per screen or per reusable component; group in `OneTake/Features/<Feature>/` (see [CODEMAP.md](CODEMAP.md)). Small subviews that only serve one screen live in the same file; shared ones get their own file.
- **MUST:** No `AnyView`. Use `@ViewBuilder`, `if/else`, `Group`, or generics to keep type identity (§14.3).

### 4.2 The view header contract

Every file that owns a responsibility gets a meaningful header (3–6 lines) — what it owns, why the design choice, and a doc link. **MUST follow the template from [AGENTS.md](../AGENTS.md) §6:**

```swift
//
//  ScriptRow.swift
//  OneTake
//
//  Owns: A single script row in the library list — title, snippet, category, date.
//  Why: Separate struct (not a helper func) so it gets its own identity, state,
//       and preview; context menu groups actions per HIG.
//  See: docs/SWIFTUI_GUIDELINES.md §4.2 + docs/ARCHITECTURE.md §7
//
```

### 4.3 Previews

- **SHOULD:** Every view ships a `#Preview` with realistic mock data. Use `modelContainer(for:inMemory:)` for SwiftData-driven views, `.environment()` for services.
- **SHOULD:** Preview multiple states: empty, populated, dark mode, largest Dynamic Type size (`.environment(\.dynamicTypeSize, .accessibility5)`), and the state that historically breaks layout.

### 4.4 @Entry / environment

- **SHOULD:** Use `EnvironmentValues` extensions (`@Entry` macro) for cross-cutting concerns rather than singletons.
- **MUST:** No global mutable state for view concerns; `@AppStorage`/`@SceneStorage` only for user preferences and restoration (§13.5).

---

## 5. Layout, Spacing & Ergonomics

### 5.1 Safe areas and edges

- **MUST:** Respect system safe areas. Only ignore them when drawing full-bleed content (camera preview, video) and then re-inset interactive controls inside the safe area.
- **SHOULD:** Use system-provided layout containers (`List`, `Form`, `NavigationStack`, `TabView`) which handle insets for you. Custom `ScrollView` content uses `safeAreaInset` for pinned controls (bottom bars) instead of overlays with manual padding.
- **MUST:** No hardcoded magic padding tied to a specific device. Use `EdgeInsets`/`padding` semantics and let the system inset for home indicator, Dynamic Type, and rotation.

### 5.2 Touch targets

- **MUST:** All interactive elements have a hit target of at least **44×44pt** (use `.contentShape` when a small visual needs a larger tap area).
- **MUST:** Place primary actions where thumbs reach — bottom half / trailing edge; keep destructive actions out of accidental-tap zones.
- **SHOULD:** Support standard gestures people expect: swipe-to-delete / swipe actions on list rows, pull-to-refresh, swipe-back navigation.

### 5.3 Hierarchy and grouping

- **MUST:** Use visual hierarchy (order, spacing, contrast) so the most important element is the most obvious one (§1.6).
- **SHOULD:** Group related controls with `Section` (in `Form`/`List`) or visual cards; label groups with short, capitalized section headers.
- **SHOULD:** Progressive disclosure — limit onscreen controls; move secondary detail into `Menu`, `contextMenu`, disclosure groups, or a detail screen.

### 5.4 Adaptivity

- **MUST:** Views must render correctly in portrait and landscape (or lock the orientation explicitly via `Info.plist` and honor the launch rule in §17.2).
- **MUST:** Never truncate or overlap content at Dynamic Type accessibility sizes; reflow using `ViewThatFits`, custom `Layout`, or switching from HStack to VStack at size classes.
- **SHOULD:** Animate layout changes (rotation, size class) implicitly — natural transitions preserve context (§1.5).

---

## 6. Color & Theming

- **MUST:** Use **semantic system colors** (`Color.primary`, `.secondary`, `.tint`, `.background`, `.separator`, `Label`/`Fill` styles) or the app's theme tokens from [`AppTheme.swift`](../OneTake/Core/Theme/AppTheme.swift): `Color.appAccent` (brand green #195636) and `Color.appSecondary` (brand yellow #FCCD03). **No hardcoded hex/RGB in views.**
- **MUST:** Both semantic and brand colors must be defined in the asset catalog with light/dark variants so Dark Mode adapts automatically. Brand `appSecondary` needs dark text for contrast when used as a background.
- **SHOULD:** Convey state with more than color — add symbols, text, or shape so color-blind users get the same information (§8).
- **SHOULD:** Tint interactive elements consistently via the app-level `.tint(.appAccent)` (already applied at the root). Only deviate per-control with intent (destructive = `.red`, recording = `appSecondary`).

---

## 7. Typography

- **MUST:** System text styles only — `.font(.headline)`, `.title`, `.body`, `.caption`, etc. System fonts scale with Dynamic Type; custom fixed sizes break accessibility (§8).
- **MUST:** No custom fonts unless a brand decision is made explicitly (none in OneTake today).
- **SHOULD:** Map importance to text style: screen title → `.largeTitle` (system places it in the nav bar), content → `.body`, supplementary → `.footnote`/`.caption`. Hierarchy through style, not arbitrary sizes.
- **SHOULD:** Keep copy **concise and plain** (§1.6): sentence case labels, verbs for buttons ("Save Take", not "Saved"), no jargon ("Blade" is a domain term used deliberately — pair with explanatory footnote on first use).
- **MUST:** Localizable strings — all user-facing copy goes through `Text("...")` string literals (localizable by default) or `String(localized:)`; never build UI strings by concatenation.

---

## 8. Accessibility & Inclusivity

Treat accessibility as a priority from the start. Designing inclusively reaches the broadest possible audience and creates a better experience for all.

- **MUST:** Every interactive element has an accessibility label (and value/traits where appropriate). Icon-only buttons MUST have `.accessibilityLabel("Record")` — never let VoiceOver read "button" alone.
- **MUST:** Respect contrast: text meets at least 4.5:1 (large text 3:1) in both appearances. Test with Increase Contrast and in Dark Mode.
- **MUST:** Hit targets ≥44pt (§5.2). Provide `.accessibilityAddTraits(.isButton)` for custom tappable shapes.
- **MUST:** Meaningful VoiceOver order: `accessibilityElement(children: .combine)` for list rows so each row reads as one unit; use `.accessibilitySortPriority` where the visual order misleads.
- **MUST:** Honor Reduce Motion — wrap nonessential animation in `if !accessibilityReduceMotion` / `@Environment(\.accessibilityReduceMotion)` (§12.4).
- **SHOULD:** Support Dynamic Type to at least `accessibility5` in previews; verify no clipping.
- **SHOULD:** Video content (takes) gets captions/transcript affordances where feasible; audio cues are never the only feedback channel.
- **SHOULD:** Test with VoiceOver on device for every new screen — cheap to verify, expensive to retrofit.

---

## 9. Navigation & Presentation

OneTake uses the unified 4-tab shell (`TabView(sidebarAdaptable)`, Liquid Glass on iOS 26) with per-tab `NavigationPath`. Keep navigation HIG-native and consistent (§1.4):

- **MUST:** `NavigationStack` per tab with `navigationDestination(for:)` — typed routes only, no string paths. Sheets/`fullScreenCover` only for modal tasks.
- **Sheet vs full screen — choose by intent:**
  - **Sheet** (`.sheet`): focused, completable secondary task; people expect drag-to-dismiss; keep it under ~one screen-height. `formSheet`/`presentationDetents` when a smaller grab-and-go surface fits.
  - **Full screen cover**: immersive experiences where dismissal is deliberate — camera capture (`StudioView`), video review. Provide an obvious dismiss control and handle drag-to-dismiss off explicitly.
  - **Alert / `ConfirmationDialog`**: urgent info or a decision. Never for anything that should be inline.
- **MUST:** Consistent placement across screens: primary action = trailing nav-bar button; row actions = context menu + swipe actions; destructive = inside a confirmation.
- **MUST:** State restoration — each tab's `NavigationPath` and `@SceneStorage("selectedTab")` must survive relaunch (§13.5). People should return exactly where they left off — scroll position, selected tab, open editors.
- **SHOULD:** One toolbar per screen; group related toolbar items with `ToolbarSpacer`/sections; overflow into `Menu` rather than stacking 5+ icons.
- **SHOULD:** Deep links / cross-tab jumps go through the established pattern (e.g., `Notification.Name.showStudio` → `selectedTab = .studio`), never by reaching into another tab's state.

---

## 10. Controls, Components & Metaphors

### 10.1 Native first

- **MUST:** Use the native SwiftUI control for the job before building custom: `Button`, `Toggle`, `Picker` (menu/segmented/wheel), `Slider`, `Stepper`, `Menu`, `Search `, `List`/`Form`, `Table` (not on iPhone), `ContentUnavailableView` for empty states.
- **MUST:** Use **SF Symbols** for iconography — correct name, correct weight/size matching adjacent text (`Label`, `Image(systemName:)` with `.symbolVariant`/`.imageScale`). Don't reinvent common action icons (trash = delete, §1.4).
- **SHOULD:** `Label` (icon + title) over separate `Image`+`Text` pairs.

### 10.2 Metaphors & consistency

- **MUST:** Familiar symbols do what people expect — trash deletes, folder groups, filmstrip = takes. A metaphor must draw on something people know and behave predictably.
- **MUST:** Same-looking controls behave the same everywhere in the app (§1.4). Audit before adding a variant: does `LUTSwatchView` / `TrimScrubberView` / a row already exist?

### 10.3 Lists and rows

- **SHOULD:** Use `List` with `swipeActions` and `contextMenu` for row actions; group menus with `Menu { Section("Organize") { … } Section("Destructive") { role: .destructive } }` (OneTake convention — see `MyTakesView`).
- **MUST:** Empty states use `ContentUnavailableView` ("No Takes Yet", icon, action button) — never a bare blank screen (§1.6, §11.3).

---

## 11. Feedback, Errors & Forgiveness

### 11.1 Immediate feedback

- **MUST:** Every interaction acknowledges immediately: button press states (system handles), progress (`ProgressView` for waits > ~1s), recording indicator, haptics for significant state changes (use the shared `Haptics` service).
- **MUST:** Never leave the UI unresponsive — all work off the main actor; the UI must render every frame while a task runs (§14).
- **SHOULD:** Show clear signals when content changes (count badges, timestamps, transitions) so people stay informed and in control (§1.4).

### 11.2 Destructive actions & forgiveness

- **MUST:** Destructive controls declare `.role(.destructive)` / `.foregroundColor(.red)` and live grouped at the bottom of menus, away from primary actions.
- **MUST:** One of: (a) confirmation before acting, or (b) action executes with immediate **Undo** affordance (undo badge/snackbar, 3–5 s). Choose (b) for cheap operations (hide, reorder, rename), (a) for irreversible loss of recorded media (delete Take file).
- **MUST:** For long operations (export, save), show progress, allow cancel, and never block leaving the screen if the task can safely continue in background.

### 11.3 Errors

- **MUST:** Never show a raw error string / `String(describing: error)`. Map to human language: *what happened* + *what to do next* ("Couldn't save the take. Your recording is safe — try again.") — plain, no jargon, no blame.
- **SHOULD:** Offer recovery right in the message (Retry / Open Settings when a permission is the cause).
- **MUST:** Missing-content states (video file moved) render an explicit, friendly row state, not a crash or silent blank (see `MyTakesView` file-missing handling).

---

## 12. Motion & Animation

Motion should feel fluid and provide immediate, natural feedback (§1.7) — and preserve context across changes (§1.5).

- **SHOULD:** Prefer implicit animation (`withAnimation` / `.animation(_:value:)` bound to a value) — springs for interactive/positional changes, ease curves for fades; never linear springs on gestural content.
- **MUST:** Animate state transitions that move or remove content (list updates with `animation` on the container, sheet detents) so people can track what changed.
- **SHOULD:** Gesture-driven controls (trim handles, scrubbers) update continuously with the finger — no detached indicator; use `DragGesture(minimumDistance: 0)` + `@GestureState` for interruptible behavior.
- **MUST:** Respect Reduce Motion and `UIAccessibility.isReduceMotionEnabled` — provide a crossfade or instant change instead of large movement (§8).
- **MUST NOT:** Animate for delight's sake in a task path (recording HUD, trim editing). Delight moments live where emotion is the point (first-run, success states) and never delay interaction (§1.8).

---

## 13. State & Data Flow

### 13.1 Ownership rules

| Data | Tool |
|---|---|
| View-local UI state | `@State` |
| Passed-in model binding | `@Bindable` (Observation) |
| Shared service (capture, export) | `@Observable` class injected via `.environment()` |
| SwiftData models | `@Model` + `@Query` (source of truth, see [PERSISTENCE.md](PERSISTENCE.md)) |
| Small preferences | `@AppStorage` |
| Per-scene restoration | `@SceneStorage` (tab, nav selection) |
| Cross-tab signals | `NotificationCenter` (`Notification.Name.showStudio` pattern) |

- **MUST:** Bodies stay pure — no side effects, file I/O, or heavy computation in `body`. Compute via `@State` + `.task`/`onAppear`-launched tasks.
- **MUST:** `@Observable` over `ObservableObject` (SwiftLint rule). `@Published` appears only in legacy-compat code.
- **SHOULD:** Dependencies flow down (view → child views), events flow up (closures/actions). Avoid `Binding` drilling more than two levels; lift state to the nearest common owner.

### 13.2 Async work

- **MUST:** Use `.task` (view-lifetime-scoped, auto-canceling) over `onAppear { Task { } }` fire-and-forget.
- **MUST:** Long tasks publish progress through an `@Observable` service; views render it. No spinners that block other UI.
- **MUST:** All `AVCaptureSession`/`AVAsset` work stays in the established services (`CaptureService`, `ExportService`) — never in a view.

### 13.3 Data-driven UI

- **MUST:** `@Query`/`@Bindable` reactivity is the update mechanism. Don't cache model data in `@State` duplicates; derive with computed properties.

### 13.4 Concurrency & main actor

- **MUST:** With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, mark CPU/media workers explicitly (`nonisolated`, `@concurrent`, background actors); UI-touching code is main-actor by default. No priority inversion — use `DispatchQueue`/structured concurrency correctly (`sync` when waiting on the main thread's behalf; correct QoS propagation).

### 13.5 Restoration

- **MUST:** Every navigation container (`selectedTab`, per-tab `NavigationPath`) and transient UI (open editor + its draft text) restores on relaunch via `@SceneStorage`/`@AppStorage` + persisted model state. People never retrace steps (§1.5, §17.3).

---

## 14. Performance

Launch and interaction performance are part of craft. Apply Apple's **minimize → prioritize → optimize** discipline to launch *and* every view.

### 14.1 Launch (target: first frame in ~400 ms)

- Understand the phases: system interface (dyld) → static runtime init → UIKit/App init (`didFinishLaunching` / `willConnectToSession`) → **first frame render** → extended (async data).
- **MUST:** App init (in SwiftUI: `init()` of `App`, root view init, `ModelContainer` setup) does only what's needed to show the first frame. Everything else is deferred — background task, lazy, or on-demand.
  - No pre-warming features/views that aren't on the first screen.
  - No blocking the main thread with file/network I/O during init.
- **MUST:** Avoid linking unused frameworks; no `dlopen`/`NSbundleLoad` patterns; hard-link dependencies (N/A in OneTake's zero-dep world — keep it that way).
- **MUST:** First screen data — fetch only what the first frame shows (first ~20 rows), then load the rest lazily in the background. `@Query` with `fetchLimit` where lists are large.
- **SHOULD:** Measure, don't estimate: use the Instruments **App Launch** template, and `XCTest` app-launch performance measurements on a consistent device set (rebooted, airplane mode, release build, warm launches). Regressions of 2 ms add up — catch them when they're introduced.

### 14.2 View body cost

- **MUST:** `body` is cheap: no sorting/filtering heavy arrays per render — precompute in the model/service or memoize (`@State` + `.task`).
- **SHOULD:** Flatten hierarchies; lazily load (`LazyVStack`/`List`) long or offscreen content; avoid deep `if/else` chains that re-diff large subtrees.

### 14.3 Identity & structural efficiency

- **MUST:** Stable identity in collections: `id: \.persistentModelID` for `@Model` lists (never `id: \.self` on reference-ish data that mutates), so updates animate correctly and don't rebuild the world.
- **MUST:** No `AnyView` — it erases diffing. Use conditional `@ViewBuilder` blocks (different types are fine; they compare as distinct branches).

### 14.4 Media & graphics

- **MUST:** LUT thumbnails and any pixel work run through the established providers (`LUTThumbnailProvider` — cached 40×24 CGImage); never render CoreImage per frame in `body`.
- **MUST:** Video playback surfaces use `AVKit`'s `VideoPlayer`; custom compositing only at export time (`ExportService`), not in the preview path.

---

## 15. First Launch & Onboarding (Love at First Launch)

Your app's launch is the person's first experience with it. First impressions matter because they could also be your last — the App Store has millions of alternatives.

- **MUST: Lead with content.** No sign-in wall, no permission gauntlet, no tutorial on first open. People land straight in a usable surface (their script library / takes — even empty, show the shape of the value with a great empty state). Registration/permission comes at the moment of action ("Save to Photos" → permission), when the benefit is visible.
- **MUST: Teach through interaction, not instruction.** Strive for interfaces so intuitive no upfront instruction is needed. If education is required, make it interactive and brief — layered into the experience (the first script created *is* the onboarding), not floating tooltips or hand-holding. Never a blocking carousel of screenshots.
- **MUST: Permission timing.** Ask on an as-needed basis, in context, immediately before the feature that needs it. Make value visible before asking; reinforce it right after granting. If the app genuinely offers zero value without a permission (unlikely for OneTake), ask once at launch with a clear explanation of what's exchanged.
- **SHOULD: No splash/branding screens.** The system launch screen (below) hands off directly to real content.

## 16. Privacy & Permissions

- **MUST:** Only request what the product needs (OneTake: camera, microphone, photo-add — nothing else). Keep `Info.plist` usage strings human, specific, and current: *"Used to record your takes while you read the prompter"* — not vague boilerplate.
- **MUST:** When a permission is denied, provide a graceful degraded path + a way to open Settings from context; never trap the person in a loop of reminders.
- **MUST:** Be transparent about data: OneTake stores everything on device; any future analytics/telemetry requires a clear rationale and an opt-out, surfaced in Profile (§1.3).
- **MUST:** Anticipate misuse (§1.3): recorded takes stay local until the person explicitly exports; no silent background upload. Ever.

---

## 17. Launching Behavior (system-level)

### 17.1 Launch instantly

- People want to interact right away; don't make them wait more than a couple of seconds, ever.

### 17.2 Launch screen

- iOS shows the launch screen the moment the app starts and quickly replaces it with the first screen. Its **sole function** is to make the app feel instant — it is *not* a branding or artistic opportunity.
- **MUST:** Design the launch screen (in the asset catalog / `Info.plist` `UILaunchScreen`) nearly identical to the app's first screen — matching layout skeleton, orientation, and appearance (light/dark). Different-looking elements cause an unpleasant flash on transition.
- **MUST NOT:** Put text on the launch screen (it can't be localized), logos, or "About"-style branding; don't make it look like a splash screen.

### 17.3 Restore state

- **MUST:** Restore the previous state when the app restarts — selected tab, nav path per tab, scroll position, editor drafts. Never make people retrace steps (§13.5).

---

## 18. Definition of Done — View Review Checklist

Run before opening any PR containing view code:

**Design principles**
- [ ] Purpose stated in header; nothing un-necessary shipped (§1.1, §1.6)
- [ ] Destructive actions are forgivable — confirm and/or undo (§1.2, §11.2)
- [ ] No permission/data ask without visible value & right timing (§1.3, §16)
- [ ] Consistent metaphors, placement, and behavior with the rest of the app (§1.4)
- [ ] Works in Dark Mode, Dynamic Type (incl. `accessibility5`), landscape/locked-portrait as designed, Reduce Motion (§1.5, §8, §12)

**Code quality**
- [ ] `struct` views, no helper-func views, no `AnyView` (§4.1)
- [ ] Header comment present & docs linked (§4.2, [AGENTS.md](../AGENTS.md) §6)
- [ ] `#Preview` with mock data incl. edge states (§4.3)
- [ ] Semantic colors/theme tokens only; system text styles only (§6, §7)
- [ ] 44pt targets, safe areas, swipe/context actions (§5, §10.3)
- [ ] VoiceOver labels/traits/order verified on device (§8)
- [ ] Native control chosen first; SF Symbols correct (§10.1)
- [ ] Typed `NavigationStack` routes; sheet vs full-screen chosen by intent (§9)
- [ ] `body` pure; async work in `.task`/services; stable IDs in lists (§13, §14)

**Performance & launch**
- [ ] No new first-screen work; first frame unaffected (§14.1)
- [ ] No heavy compute in `body`; lazy lists for long content (§14.2)
- [ ] Media work through services/providers (§14.4)

**Process**
- [ ] `swiftlint lint OneTake --quiet` → 0 violations; `swiftformat --lint .` → clean
- [ ] `xcodebuild test ... -only-testing:OneTakeTests` passes
- [ ] New file added to `docs/CODEMAP.md`; feature spec delta in `openspec/` if behavior-shaping

---

*Last updated: 2026-09-06 — created during `trim-blade-luts-pricing`. Sources: Apple HIG (Design Principles, Designing for iOS, Launching), WWDC sessions "Principles of Great Design", "Love at First Launch", "Optimizing App Launch". Keep this file in sync with [AGENTS.md](../AGENTS.md) and [ARCHITECTURE.md](ARCHITECTURE.md).*
