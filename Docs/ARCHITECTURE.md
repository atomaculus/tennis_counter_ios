# Architecture

PLAYCE iOS mirrors the Android repo architecture without mixing phone and watch responsibilities.

## Module Boundaries

```text
Shared/   Rules, models, persistence contracts, sync payloads
iOS/      iPhone UI, local history owner, premium UI, export/share, Garmin companion bridge
Watch/    Apple Watch scorer, HealthKit workout lifecycle, watch UI
```

Rules:

- `Shared/` must not import SwiftUI-only app screens.
- `iOS/` must not own watch-specific UI or HealthKit workout lifecycle.
- `Watch/` must not own phone-only screens such as History, Detail, Stats or Share.
- Sync payloads belong in `Shared/` because both targets encode/decode them.

## Shared Layer

Key files:

- `Shared/PlayceModels.swift`
  - Match format presets.
  - Finished match records.
  - Stats and share-card data.
  - WatchConnectivity payload structs.
- `Shared/TennisScoringEngine.swift`
  - Pure scoring engine.
  - `ScoreboardController` state wrapper used by iPhone and Watch.
- `Shared/PlayceStores.swift`
  - `PremiumStore`.
  - `MatchHistoryStore`.
  - `MatchCSVExporter`.
  - `ConnectivityCoordinator`.

The scoring engine is intentionally pure enough to test without iOS/watchOS runtime dependencies.

## iPhone Layer

Key file:

- `iOS/PlayceIOSApp.swift`

Responsibilities:

- Configure match names and format.
- Run local phone counter.
- Send config to Watch.
- Send config to Garmin through Connect IQ.
- Show read-only live score when Watch is source of truth.
- Show read-only live score when Garmin is source of truth.
- Own local match history.
- Show detail, stats, CSV export and share card.
- Present premium gate and StoreKit actions.

The iPhone is the durable storage owner for finished matches.

## Watch Layer

Key file:

- `Watch/PlayceWatchApp.swift`

Responsibilities:

- Score a live match from the wrist.
- Show compact scoring/timer/sync UI.
- Apply config received from iPhone.
- Broadcast live score to iPhone.
- Queue finished matches for iPhone save.
- Manage HealthKit workout session lifecycle.

The Watch can count a match independently, but saved match history remains phone-owned.

## Garmin Layer

Key file:

- `iOS/GarminConnectivityCoordinator.swift`

Responsibilities:

- Initialize the Garmin Connect IQ Companion App SDK on iPhone.
- Launch Garmin Connect Mobile for device selection via URL scheme `playce-ciq`.
- Register selected `IQDevice` / `IQApp` pairs for device and app messages.
- Send match config envelopes to the Garmin watch.
- Receive live score and finished-match envelopes from the Garmin watch.
- Store finished Garmin matches through the same phone-owned history path and send ACK envelopes.

The Garmin watch-side app lives outside this repo in the sibling Connect IQ project. Its app id must match `c4f18a72-b93e-4d6f-a1c8-e5b2079d3a44`.

## Sync Flow

Live score:

```text
Watch ScoreboardController
  -> LiveMatchPayload
  -> WCSession application context
  -> iPhone live score UI
```

Config:

```text
iPhone setup
  -> MatchConfigPayload
  -> WCSession application context
  -> Watch ScoreboardController reset/apply config
```

Finished match:

```text
Watch FinishedMatchRecord
  -> sendMessageData when reachable
  -> transferUserInfo fallback
  -> iPhone MatchHistoryStore.upsert
  -> MatchSyncAckPayload
  -> Watch clears pending item
```

Garmin uses the same semantic payloads through Connect IQ envelopes:

```text
Garmin watch
  -> /playce/live or /match_finished envelope
  -> GarminConnectivityCoordinator
  -> ConnectivityCoordinator / MatchHistoryStore
  -> /match_finished_ack envelope
  -> Garmin watch clears pending item
```

Idempotency is handled with `FinishedMatchRecord.idempotencyKey`.

## Adding New Match Formats

1. Add or update the format in `Shared/PlayceModels.swift`.
2. Update `ScoringEngine` rules in `Shared/TennisScoringEngine.swift` if the format changes scoring behavior.
3. Add tests in `Tests/ScoringEngineTests.swift`.
4. Expose the format in iPhone setup UI.
5. Confirm the Watch receives it through `MatchConfigPayload`.

## Known Limitations

- Undo UX is not yet identical to Android Wear: Android uses long press on score buttons; iOS/watchOS currently exposes explicit undo buttons.
- Spectator second-watch mode is not ported because watchOS pairing topology differs from Wear OS Data Layer.
- Real StoreKit requires App Store Connect product setup.
- HealthKit entitlement and privacy strings are present, but real-device signing must still be validated.
- Garmin Connect IQ compile-time integration is present, but end-to-end validation requires Garmin Connect Mobile, a physical Garmin device and the sibling watch app installed.
