# Design: content-first launch

## Pre-Implementation Gate (§3) answers
1. **Purpose:** first frame is usable content; zero forced steps. Not building: any tutorial, splash, or upfront permission screen.
2. **Agency:** nothing forced; every permission is grantable/deniable in context with a Settings recovery path.
3. **Responsibility:** camera/mic ask when Studio opens (preview visible), Photos at save (destination visible). Denied → alert + Open Settings, never a loop.
4. **Familiarity:** standard tab shell + `ContentUnavailableView` empty states already used elsewhere; no symbols repurposed.
5. **Flexibility:** shell already handles Dark Mode/Dynamic Type/VoiceOver; no new state to restore (one less flag).
6. **Simplicity:** net deletion (~150 lines view + gate + replay + dummy row); copy unchanged elsewhere.
7. **Craft:** semantic colors/system styles untouched; no new UI to polish.
8. **Delight:** the defining moment is instant usefulness — app opens, library invites creation.

## Decisions
- **Delete, don't hide:** remove the view file + gate + tests rather than
  feature-flagging; dead code rots and the future paywall wall is a separate
  change with its own spec.
- **Keep permission code where it lives:** `CaptureService.check/requestPermission`
  + `StudioView.showPermissionDenied` alert and `ExportService.saveToPhotos`
  add-only request already satisfy §15/§16; no changes needed there.
- **UI tests assert absence:** `FirstLaunchUITests` fails if Skip/Get Started
  ever reappear on first frame — regression net for §15.

## Risks
- Existing installs keep an unread `hasSeenOnboarding` key in defaults:
  harmless, never read, no migration needed.
- Marketing desire for a brand splash: rejected by §15 SHOULD + §17.2
  (launch screen is not a branding opportunity).

## Migration
Single slice, independently revertible (`git revert` restores the gate).
