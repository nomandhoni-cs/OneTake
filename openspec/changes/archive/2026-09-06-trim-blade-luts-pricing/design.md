## Context

Review already models multi-cut timelines (`bladeCuts`, `bladeSegments()`,
compaction helpers, undo stack, one-pass export composition) — but tracing the
delete path exposes a correctness bug: deleting middle segment [5-12s] from
cuts [5,12] rewrites cuts to [5], whose derived segments [0-5]+[5-20] still
contain the "deleted" footage, and `exportTake` inserts those ranges verbatim.
Result: the UI drops a segment row while the export keeps every second. Cut
positions alone cannot express "keep both sides, drop the middle" — the model
needs explicit source ranges. Everything else in this change is presentation
(actions row, timeline framing, LUT shelf) plus a review-only pricing plan.

## Goals / Non-Goals

**Goals:**

- Single-line action buttons at 320–430pt widths with no behavior change.
- Deletion that actually deletes: explicit per-segment source ranges, any
  segment removable (except the sole survivor), undo preserved.
- Timeline framing that shows what the model holds: identity chips, dividers,
  selection, playhead.
- 10-preset LUT shelf generated reproducibly; size-aware loader; ≈3 MB cost.
- A concrete, reviewable pricing plan delivered as docs — no paywall code.

**Non-Goals:**

- StoreKit code, paywall UI, entitlement checks, receipt validation, analytics.
- New capture formats, cloud sync, social publishing SDKs.
- Changing trim/export semantics, or the schema
  version (the model fix is additive per `docs/PERSISTENCE.md` §4).

## Decisions

### 1. Actions row: shrink, don't wrap

`Label("Save as New Take")` + `Label("Replace")` share one `HStack` with
`.frame(maxWidth: .infinity)` each; on 320pt screens the longer label wraps.
Fix: `.lineLimit(1)` + `.minimumScaleFactor(0.85)` on both labels (keep
`.bordered` / `.borderedProminent` styles and disabled states).

Alternative considered: shorter copy ("Save New"). Rejected — existing copy is
clear; scaling to 85% stays legible and preserves meaning.

### 2. Blade model: explicit `BladeSegment` ranges (the correctness fix)

New `struct BladeSegment: Codable, Equatable { var start, duration: Double }`
plus `Take.segments: [BladeSegment]? = nil` (additive Optional — lightweight
migration, no version bump; existing stores read `nil` and derive from cuts).

- `bladeSegments()` prefers stored ranges (mapped to `CMTimeRange`), falling
  back to cut-derivation when `nil` — zero call-site churn in export, preview,
  and duration math.
- `bladeCuts` stays synced as internal boundaries for the scrubber dividers;
  a `syncCutsFromSegments()` invariant runs after every mutation.
- Split at `t`: find the containing stored range (or derived span), replace it
  with two ranges; dedupe/0.1s rules unchanged; auto-select the right half.
- Delete index `i`: remove the element (deny when count == 1); no shifting
  arithmetic, no timebase confusion — removal IS the compaction.
- Trim interplay: clip stored ranges to `trimRange` (drop non-overlapping,
  clamp partial overlaps); undo stack becomes `[[BladeSegment]?]` snapshots.
- First blade edit on a legacy take materializes stored ranges from the
  derived spans once, then operates on ranges thereafter.

Alternative considered: fixing the shift math in cut-space. Rejected — cut
positions fundamentally cannot express interior deletion (proven by trace);
patching would add special cases instead of removing the wrong abstraction.

### 3. Blade framing: show the model

Timeline additions (all in `TrimScrubberView`, no model impact): per-segment
`index/total + duration` chip on the selected segment plus a compact duration
tag per segment; keep 2pt white dividers, yellow selection outline, and clamp
the playhead so it never renders under a trim handle. Split/Delete buttons
keep existing disabled rules, extended to the any-segment model (Delete denied
only for the sole survivor). A regression test locks the fixed behavior:
delete-middle then assert exported ranges exclude the interval.

Alternative considered: per-segment thumbnail strip. Rejected for v1 — cost
(asset image generators per segment) outweighs clarity gain; chips suffice.

### 4. LUTs: parametric generation at SIZE 32 + size-aware loader

New presets (rawValue → display): `golden_hour` (Golden Hour), `teal_orange`
(Teal & Orange), `faded_film` (Faded Film), `noir` (Noir Punch B&W),
`vibrant_pop` (Vibrant Pop), `cool_morning` (Cool Morning). Each defined as
lift/gamma/gain + saturation + optional monochrome mix in a checked-in Python
generator (`tools/generate_luts.py`), emitting `LUT_3D_SIZE 32` cubes (~500 KB
each). 64³ stays for the original four (untouched files).

`LUTCubeLoader` drops the hardcoded 64: sniff each file — Adobe text (has a
`LUT_3D_SIZE N` line → parse triplets to RGBA float32, R fastest) versus
legacy raw binary (`byteCount == N³×16` for N in 16/32/64 → pass through with
that N; 4 MB means 64). Missing/unparseable files keep today's behavior
(placeholder swatch, Natural-export fallback). New generator emits Adobe text
at SIZE 32 (~800 KB each); same parse feeds the thumbnail renderer. Cache keys and the
missing-file → placeholder → Natural-export fallback are unchanged, as are
`LUTPreset`'s `Codable`/`CaseIterable` roles (6 new cases appended).

Alternative considered: shipping 64³ for all ten (+25 MB). Rejected — 32³ is
visually indistinguishable for stylistic grades and keeps the bundle lean.

### 5. Pricing plan (REVIEW ONLY — no implementation in this change)

**Recommended model: low-price paid app with a native 7-day free trial.**

- **Trial, not a counter:** a hand-rolled "10 free videos" counter lives
  on-device and resets on reinstall; a native trial is tracked by Apple per
  Apple ID (one trial per user, enforced by the store), needs no counting
  code, warnings UI, or "what counts" edge cases. Full features during trial.
- **Lineup (starting points to validate):** Annual **$12.99/yr** (~$1.08/mo,
  carries the 7-day free trial) + Monthly **$1.99/mo** (no trial, steers to
  annual) + **Lifetime $39.99** one-time. All are valid App Store tiers.
  Positioned well under $8–10/mo competitors: the affordable option on purpose.
  Note the volume math (~$11 net per annual sub after Apple's cut, so this
  price wins on subscriber count).
- **Flow:** onboarding → trial offer wall ("Start free 7-day trial",
  standard card-upfront Apple sheet) → full app unlocked. Decline or let it
  lapse → view-only mode (library visible, record/export locked behind lock
  affordances → paywall). Launch itself is never blocked.
- **What's included:** everything — both studios, all 10 LUTs, 4K export,
  blade/trim, Photos save + Share. No tiers-within-tiers, no LUT packs.
- **Paywall placement (future):** trial offer wall post-onboarding, lock
  affordances on record/export when unsubscribed, a "OneTake Pro" row in
  Settings with Restore Purchases. Never blocking launch or the library.
- **Future implementation shape (not built now):** RevenueCat (works without
  auth via anonymous IDs; `logIn()` aliases later) or raw StoreKit 2 —
  `Product.products(for:)`, introductory offer on Annual,
  `Transaction.currentEntitlements`, one cached `isPro` flag (offline-safe),
  entitlement checks at record + export choke points, receipt validation via
  App Store Server API only if fraud appears, plus `paywall_shown /
  trial_started / subscribed` analytics events.
- **Why subscription over paid-upfront:** trials convert; Apple Search Ads +
  editorial both favor free-download-with-trial; lifetime captures
  anti-subscription buyers who would otherwise churn at the paywall.

Alternatives considered: paid-upfront ($9.99, rejected — kills top-of-funnel
for a camera app); ads (rejected — poisons a creation flow); hand-rolled
export counter (rejected — resettable, extra UI/code, inferior to the native
trial in every way); consumable credits (rejected — wrong mental model).

## Risks / Trade-offs

- [Risk] Model overlay diverges (`segments` vs `bladeCuts`) → Mitigation: one
  invariant function + unit tests asserting sync after every mutation.
- [Risk] Generated LUTs look amateur → Mitigation: swatch renders + TrimExport
  snapshot tests catch regressions; on-device visual QA task gates taste.
- [Risk] SIZE-32 banding on gradients → Mitigation: test clips include sky/
  wall gradients; fall back to 64 for any offender (loader already handles it).
- [Risk] Segment-chip clutter on short takes → Mitigation: full chip only for
  the selected segment + compact duration tags; 44pt targets preserved.
- [Trade-off] Pricing numbers are unvalidated placeholders → explicitly marked
  as such; App Store Connect entry + competitor check happen at approval.
- [Trade-off] No paywall code now → Pro LUTs ship visible-but-free until the
  monetization change lands (documented in `docs/PRICING.md`).

## Migration Plan

1. Land actions-row fix (UI-only, zero behavior risk).
2. Land `BladeSegment` model + engine fix + regression tests (additive field,
   no version bump; legacy takes derive on first edit).
3. Land blade framing UI + spec alignment.
4. Land size-aware loader (backward compatible), then generator + 6 cubes +
   preset cases + swatches + tests.
5. Transcribe §5 verbatim into `docs/PRICING.md` (docs-only task).
6. Rollback is per-slice: each group reverts independently; cubes delete
   cleanly; model addition is inert without writers.

## Open Questions

- Final LUT display names/copy (marketing voice) — default to the six above.
- Annual/monthly/lifetime price points — validate before App Store Connect.
- Trial length (7-day default; 3-day fallback if data shows slow conversion).
