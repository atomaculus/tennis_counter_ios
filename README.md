# Playce iOS Port

Port in Swift/SwiftUI of the Android PLAYCE app found in `C:\Users\atoma\OneDrive\Desktop\Tenis counter`.

What is included here:
- iPhone app structure in SwiftUI
- Apple Watch app structure in SwiftUI
- Shared tennis scoring engine
- WatchConnectivity sync for live score and finished matches
- Local match history persistence
- Premium gate store stubbed with local persistence
- HealthKit workout session manager for the watch match flow
- Share card rendering for iPhone

Important constraints respected:
- Nothing in `C:\Users\atoma\OneDrive\Desktop\Tenis counter` was modified
- This directory is the only one changed

Because this machine is Windows, no Xcode project was generated or validated here. The source files are organized so they can be added to an iOS + watchOS Xcode project on a Mac.

Suggested Xcode target layout:
- iOS target: include `Shared/` + `iOS/`
- watchOS target: include `Shared/` + `Watch/`

Primary parity with Android:
- Watch is the scorer device
- iPhone shows read-only live score when the watch is broadcasting
- iPhone stores finished matches in history
- Premium gate protects history/detail/share flows
- iPhone free mode keeps a local manual counter

Known platform difference:
- The Android "second spectator watch" topology does not map cleanly to watchOS. This port keeps the main watch scorer + iPhone observer flow.
