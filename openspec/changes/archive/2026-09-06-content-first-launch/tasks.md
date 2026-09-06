## 1. Remove the gate and the flow
- [x] 1.1 `ContentView`: drop `hasSeenOnboarding` flag + branch → shell always
- [x] 1.2 Delete `Features/Onboarding/OnboardingView.swift` (+ empty dir)
- [x] 1.3 `ProfileView`: drop replay row + flag; drop dummy Account section

## 2. First-launch UI tests
- [x] 2.1 Rewrite `OnboardingUITests` → `FirstLaunchUITests` (tabs on first frame, absence of Skip/Get Started, teaching empty state)

## 3. Gates
- [x] 3.1 `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test`
- [x] 3.2 `openspec validate --changes`; update `docs/CODEMAP.md` (+ ARCHITECTURE/AGENTS if referenced)
