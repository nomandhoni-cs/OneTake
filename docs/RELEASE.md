# Release — OneTake (TestFlight & App Store)

> Bare-minimum CLI for every new version. iOS 18.6 min, bundle `com.nomandhoni.onetake`, team `8ZL69D7NJ5`.

## 1. Bump version

```bash
# Marketing version (App Store 1.0.0 → 1.0.1) — edit manually:
# OneTake.xcodeproj → OneTake target → General → Version 1.0.0
# or: agvtool new-marketing-version 1.0.1

# Build number — MUST bump for every upload (1 → 2 → 3):
xcrun agvtool next-version -all
# check:
xcrun agvtool what-version -terse && xcrun agvtool what-marketing-version -terse
```

## 2. Commit

```bash
git add -A
git commit -m "chore: bump 1.0.0 (2) for TestFlight"
git push origin main
```

## 3. Archive + Export (no iPhone needed)

```bash
# ensure API key is where altool expects it (your iCloud file)
mkdir -p ~/.appstoreconnect/private_keys
cp ~/Library/Mobile\ Documents/com~apple~CloudDocs/AuthKey_X3H8Q64N5G.p8 ~/.appstoreconnect/private_keys/

# clean build
xcodebuild archive -project OneTake.xcodeproj -scheme OneTake -configuration Release \
  -archivePath build/OneTake.xcarchive -destination 'generic/platform=iOS'

xcodebuild -exportArchive -archivePath build/OneTake.xcarchive \
  -exportPath build -exportOptionsPlist ci/ExportOptions.plist
# → build/OneTake.ipa
```

`ci/ExportOptions.plist` is already `method=app-store, teamID=8ZL69D7NJ5, uploadSymbols=true`.

## 4. Upload to App Store Connect

```bash
# Issuer ID from App Store Connect → Team Keys page
xcrun altool --upload-app -f build/OneTake.ipa -t ios \
  --apiKey X3H8Q64N5G --apiIssuer 05a72672-e2a5-4865-95a3-e323ea6a4bf5 --verbose
# alternative: fastlane pilot upload --ipa build/OneTake.ipa
```

Wait 5–10 min → `App Store Connect → TestFlight → iOS builds` shows `1.0.x (y)`.

## 5. TestFlight

* `Missing Compliance` → `Manage` → `None of the algorithms mentioned above` (already bypassed next time via `ITSAppUsesNonExemptEncryption=false` in `Info.plist`)
* `Internal Testing` → add friend's Apple ID as team member *or* `External Testing → Public Link` → send link

## 6. App Store Submission (when ready)

In `App Store Connect → OneTake → 1.0 → App Information` verify:
- Name `OneTake - Teleprompter Studio` (29/30), Subtitle `Script Reader, Reaction & LUTs` (30/30)
- Privacy Policy URL `https://onetake.blinkeye.app/privacy` (+ Terms `…/terms`) live 200
- `App Privacy` = `Purchases + User ID/Device ID → App Functionality, Linked YES, Tracking NO`
- `Paid Apps` agreement Active, 3 products `Cleared for Sale` + `current` offering
- `In-App Purchases` added to version 1.0, screenshots/description filled, `1.0.0` → `Ready for Sale`

## 7. Verify locally before upload

```bash
xcodebuild -project OneTake.xcodeproj -scheme OneTake -destination 'platform=iOS Simulator,name=iPhone 17' build
export PATH="$PATH:/opt/homebrew/bin" && swiftlint lint OneTake --quiet
xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OneTakeTests
```

All must be `0 warnings / 0 violations / 62 passed`.
