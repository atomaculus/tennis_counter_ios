# Porting Notes

## Android source understood

Core Android behaviors mapped from `C:\Users\atoma\OneDrive\Desktop\Tenis counter`:
- Wear OS drives the match scoring state
- Tennis scoring rules are classic advantage scoring with:
  - points `0, 15, 30, 40, AD`
  - game win at 4+ points and 2-point margin
  - set win at 6+ games and 2-game margin
- Watch keeps a running timer and supports pause/reset
- Watch can undo the last point for either player
- Watch emits live score updates to phone
- Phone replaces its editable counter with a read-only live screen while a watch match is active
- Finished matches are stored on phone history
- Premium gating protects history, detail and share flows
- Detail view includes share-card generation and photo attachment

## iOS port choices

- `Shared/TennisScoringEngine.swift`
  - Carries the same scoring rules, timer behavior, undo, reset game and reset match.
- `Shared/PlayceStores.swift`
  - Replaces Android Data Layer + persistence with:
    - `WCSession.updateApplicationContext` for live score
    - `WCSession.transferUserInfo` for finished matches
    - JSON file persistence for saved history
    - local premium flag persistence via `UserDefaults`
- `iOS/PlayceIOSApp.swift`
  - Replicates the Android mobile experience:
    - Counter tab
    - Live read-only takeover when watch is broadcasting
    - History tab with premium lock
    - Detail screen
    - Share card rendering
- `Watch/PlayceWatchApp.swift`
  - Replicates the Android watch scorer role:
    - score entry
    - timer
    - haptics
    - finish/save flow
    - HealthKit workout session lifecycle

## Platform gap

Android supports a "spectator second watch" pattern through the Wear Data Layer broadcast model.
watchOS does not have a clean equivalent for that same topology in a standard iPhone + Apple Watch pairing setup, so this port keeps:
- Apple Watch as scorer
- iPhone as observer and history owner
