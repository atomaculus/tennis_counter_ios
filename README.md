# PLAYCE iOS - Tennis Score Tracker for iPhone & Apple Watch

iOS and watchOS port of [PLAYCE](https://github.com/atomaculus/tennis_counter), the tennis and padel score tracker originally built for Android and Wear OS.

---

## Why I built this

After shipping the Android version of PLAYCE, the natural next step was iOS. The architecture had to be rethought for Apple's ecosystem - watchOS and WatchConnectivity work differently than Wear OS, and SwiftUI has its own patterns compared to Jetpack Compose. Rather than copy-paste, this port was a deliberate platform adaptation.

---

## Features

- **Apple Watch scorer** - live point tracking from the wrist, watch is the source of truth during a match
- **iPhone observer** - read-only live score display while a match is in progress
- **Match history** - finished matches stored locally on iPhone
- **Share card** - match summary rendered and shareable from iPhone
- **HealthKit integration** - watch tracks the match as a workout session
- **Premium gate** - freemium model with local persistence; free mode keeps a manual counter on iPhone

---

## Tech stack

| Layer | Stack |
|---|---|
| Apple Watch | SwiftUI (watchOS) |
| iPhone | SwiftUI (iOS) |
| Shared logic | Swift - tennis scoring engine in `Shared/` |
| Sync | WatchConnectivity |
| Health | HealthKit workout session manager |
| Store | StoreKit (stubbed, local persistence) |

---

## Architecture

```text
Shared/   -> Tennis scoring engine, shared models
iOS/      -> iPhone screens, history, share card, premium gate
Watch/    -> Apple Watch live scorer and workout flow
```

The watch handles live scoring. The iPhone acts as companion display and storage layer for completed matches.

---

## Main flows

1. Start and score a match from Apple Watch
2. Sync the live match state to the iPhone
3. Save finished matches into local history
4. Render and share a summary card from iPhone
5. Track the session as a workout through HealthKit

---

## Platform note

This is not a direct 1:1 copy of the Android project. The core product intent is the same, but the implementation follows Apple platform conventions and capabilities.

---

## Status

The codebase is structured and feature-complete at the source level, but final Xcode project generation and device validation must be done on macOS.
