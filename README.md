# PLAYCE iOS

iOS/watchOS port of [PLAYCE Android](https://github.com/atomaculus/tennis_counter), a tennis and padel score tracker for phone and watch.

The goal of this repo is product parity with Android while respecting Apple platform boundaries:

```text
Android :shared  -> iOS Shared/
Android :mobile  -> iOS iOS/
Android :app     -> iOS Watch/
```

Keep phone-only features in `iOS/`, watch-only features in `Watch/`, and rules/models/sync contracts in `Shared/`.

## MVP Status

Implemented:

- Shared tennis scoring engine with Standard, Grand Slam and Fast4 formats.
- No-ad, tiebreak, final-set super tiebreak, replay, server and serve-side logic.
- iPhone counter with setup, timer, scoring, undo, reset, finish and save.
- Apple Watch scorer with timer, scoring, undo, reset, finish, HealthKit workout lifecycle and sync status.
- WatchConnectivity live score, config sync, finished-match transfer, retry state and ACK handling.
- Local match history with versioned JSON archive and legacy migration.
- Match detail, delete, attached photo, share card PNG.
- Stats and CSV export.
- Premium gate with StoreKit 2 product `premium_unlock` and DEBUG local unlock fallback.
- Shared assets, app icon, wordmark and English/Spanish localizable strings.
- QA and release prep docs.

Known MVP follow-ups:

- Android Wear opens undo through long press on `+A`/`+B`; this MVP still shows explicit `Undo A`/`Undo B` controls.
- A second spectator watch is not directly equivalent on standard watchOS pairing topology.
- Real StoreKit, HealthKit and WatchConnectivity must be validated with signed builds on real devices before TestFlight.
- Garmin / Connect IQ remains second priority and is tracked in `/Users/nicolasolivares/AGM/PLAN_REPLICA_IOS_PLAYCE.md`.

## Project Files

This repo uses XcodeGen. The generated Xcode project is derived from `project.yml`.

```text
Shared/       Shared scoring engine, models, stores, sync contracts
iOS/          iPhone SwiftUI app
Watch/        Apple Watch SwiftUI app and HealthKit manager
Resources/    Asset catalog, localizations, privacy manifest
Tests/        Unit tests for shared behavior
Docs/         Porting, QA, architecture and release notes
```

Current targets:

- `PlayceIOS`: iPhone app, embeds the Watch app.
- `PlayceWatchApp`: watchOS scorer app.
- `PlayceSharedTests`: unit tests for scoring, stores, stats, share data and premium.

## Local Build

Run from `/Users/nicolasolivares/AGM/tennis_counter_ios`:

```bash
xcodegen generate
xcodebuild test -project Playce.xcodeproj -scheme PlayceSharedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild -project Playce.xcodeproj -scheme PlayceIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Playce.xcodeproj -scheme PlayceWatchApp -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Last verified locally:

- `PlayceSharedTests`: 33 tests, 0 failures.
- `PlayceIOS`: simulator build succeeded.
- `PlayceWatchApp`: simulator build succeeded.
- Apple Watch Simulator smoke: app opens and renders the counter without the HealthKit crash.

## Manual QA

Use [Docs/MVP_QA_CHECKLIST.md](Docs/MVP_QA_CHECKLIST.md) for the current MVP checklist.

Main flows to validate:

1. Count a full match from iPhone.
2. Count a full match from Apple Watch.
3. Send config from iPhone to Watch.
4. Observe live Watch score on iPhone.
5. Save a finished Watch match on iPhone.
6. Open History, Detail and Stats.
7. Export CSV and share match card.
8. Verify premium locked/unlocked states.

## Release Prep

Use [Docs/RELEASE_PREP.md](Docs/RELEASE_PREP.md) before any App Store Connect work.

Current release-related files:

- `Watch/PlayceWatchApp.entitlements`: HealthKit entitlement for Watch.
- `Resources/PrivacyInfo.xcprivacy`: required reason API declaration for `UserDefaults`.
- `project.yml`: generated Info.plist keys including HealthKit usage descriptions.

Release blockers:

- Apple Developer team and signing.
- Production bundle identifiers.
- App Store Connect product `premium_unlock`.
- Privacy policy URL and App Privacy answers.
- Screenshots and metadata.
- Archive and TestFlight validation.

## Documentation

- [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md): module boundaries and data flow.
- [Docs/PORTING_NOTES.md](Docs/PORTING_NOTES.md): Android-to-iOS porting decisions.
- [Docs/MVP_QA_CHECKLIST.md](Docs/MVP_QA_CHECKLIST.md): repeatable QA checklist.
- [Docs/RELEASE_PREP.md](Docs/RELEASE_PREP.md): release prep and App Store blockers.
