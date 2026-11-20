# Tug of War — realtime multiplayer for iPhone

MoLab final project. A real-time tug-of-war you play with friends, each on their own
iPhone. Tilt the phone toward the **TUG!** arrow to pull steadily; swipe, tap, or hit the
big button for a burst. Every player is a round dot with a coloured border and their photo
(or initials) in the middle. The camera stays on *you* but always keeps the centre line or
the hole in view, panning and zooming smoothly as the rope moves.

Two arenas:

| Team Linear | Circular |
|---|---|
| Two teams on one rope. Pull the knot past your goal line. Players pick a team in the lobby, or the host splits everyone randomly. | Tug of war on a ring-shaped ledge: a hole in the middle that keeps growing, and a pit outside. Everyone holds one rope, so the ground you win is ground somebody else loses. Go over either edge and you are out. Two randomly seated teams or free-for-all; last one standing wins. |

Join a room three ways: **type the 4-letter code**, **open an AirDropped link**
(`tugofwar://join/ABCD`, the app's own URL scheme), or **tap an NFC tag** that the host
wrote the link onto. There is also an offline **practice vs bots** mode that uses the same
physics and the same room logic without a network.

Written in Swift / SwiftUI (iOS 17+). The interface is plain system UI — `Form`, `List`,
system colours, SF Symbols, `Gauge`, native sheets and toolbars — so it looks like the rest
of iOS and follows light and dark mode and Dynamic Type. Only the playing field is drawn by
hand, with a SwiftUI `Canvas`. Multiplayer is Firebase **Realtime Database** with anonymous
auth, the same approach as the class MoLobby / AnonLobby examples.

## Repo layout

```
TugOfWar.xcodeproj/        Xcode project (Firebase via Swift Package Manager)
TugOfWar/
  TugOfWarApp.swift        app entry; configures Firebase only if a plist is present
  Models/                  room / player / input / state records, local profile
  Engine/                  GameEngine (physics), Layout (geometry), CameraState
  Services/                RoomTransport protocol + Firebase and in-memory implementations,
                           anonymous auth, tilt input (CoreMotion), NFC, join links
  Session/                 RoomSession (lobby + host loop + interpolation + camera), bots
  Views/                   Home (Form), Lobby (List), Game canvas + HUD, results sheet
database.rules.json        Realtime Database rules (signed-in users only)
docs/ai-usage.md           AI assistance log (prompt + what was produced)
docs/proposal-week10.md    the original week-10 proposal and plan
```

## Setup

1. Open `TugOfWar.xcodeproj` in Xcode 16 or newer. Swift Package Manager fetches
   `firebase-ios-sdk` (13.x) on first open.
2. **Firebase config.** Drop a `GoogleService-Info.plist` into the `TugOfWar/` folder next to
   `Info.plist` (it is git-ignored and the synchronized folder picks it up automatically).
   Use the class project's plist from the private class repo, or create your own Firebase
   project and enable **Authentication → Anonymous** and **Realtime Database**. The plist
   must contain `DATABASE_URL`; if it doesn't, create the Realtime Database in the console
   and download the plist again. Without a plist the app still runs, but only practice mode.
3. If you use your own Firebase project, paste `database.rules.json` into
   *Realtime Database → Rules*.
4. Signing: set your team under *Signing & Capabilities*. NFC tag reading needs a paid
   developer team; if Xcode complains about the NFC entitlement with a Personal Team, remove
   the `com.apple.developer.nfc.readersession.formats` entry from `TugOfWar.entitlements`.
   The NFC buttons then simply report "not available".
5. Debug builds accept launch arguments (Xcode: *Edit Scheme → Run → Arguments*) that jump
   straight into a practice round, handy for demos and for the simulator:
   `--practice=circular,individual --bots=5 --autostart --autotug` (`--autotug` makes your
   own dot pull by itself). The same flags work as environment variables `TUG_PRACTICE`,
   `TUG_BOTS`, `TUG_AUTOSTART`, `TUG_AUTOTUG` (with `simctl launch`, prefix them with
   `SIMCTL_CHILD_`).
6. Run on real iPhones for tilt and NFC. The simulator has no motion sensors, so there you
   pull with swipes, taps and the TUG! button (the HUD says which inputs are live).

## How to play

1. Set your name and (optionally) a photo on the home screen.
2. **Host:** *Create a room*, pick the arena, and share the code / AirDrop the link /
   *Write tag*. **Others:** type the code, open the link, or *Tap an NFC tag*.
3. In the lobby (Team Linear) pick your team or let the host *Split randomly*. In Circular,
   teams and seats are drawn randomly when the host presses *Start round*.
4. 3-2-1, GO. Tilt toward the arrow to pull; swipe toward the arrow, tap the field or press
   **TUG!** for a burst. *recenter* re-zeroes the tilt to how you're holding the phone now.
5. The host can *Play again* (new random seats) or go *Back to lobby*. Late joiners watch
   and are seated in the next round. If the host leaves, the longest-present player takes
   over automatically.

## How the multiplayer works

Everything for a room lives under `tug/rooms/{CODE}` in Realtime Database:

| node | who writes | what |
|---|---|---|
| `meta` | host | mode, team mode, `hostId`, `status` (lobby → countdown → playing → finished), `startAt`, `round`, `winner`, `slotCount` |
| `players/{uid}` | each phone | name, tiny base64 photo, team, `slot` (−1 = not in this round), join time |
| `inputs/{uid}` | each phone, ≤10/s while playing | `pull` 0…1 from tilt, `tugs` (monotonic count of bursts) |
| `state` | host, ~12/s | knot / ring position + velocity, hole radius, eliminated players, elapsed time |

* **One phone simulates.** The host runs `GameEngine` at display rate and publishes
  `state`. Everyone else glides toward the latest `state`, extrapolated by its velocity, so
  the rope looks smooth between updates. The host uses its own input directly (no round
  trip). Answering the proposal's questions: yes, one phone computes the rope for everybody;
  inputs are sent at most 10×/s and only when they change; state goes out ~12×/s.
* **Presence.** Each phone registers `onDisconnect` removals for its player and input
  records, and the host registers `onDisconnect` → `hostId = ""`. If the host record
  disappears, the earliest-joined player claims `hostId` with a transaction and continues
  from the last published state. (A phone that reconnects after being dropped re-adds itself.)
* **Why Realtime Database and not Firestore.** The class MoLobby lobby already uses RTDB.
  Firestore is built for documents and recommends about one write per second per document;
  RTDB is a low-latency socket designed for exactly this kind of small, frequent update.
* **Transport abstraction.** `RoomTransport` is the tiny set of operations the game needs
  (set / update / read / observe / onDisconnect / compare-and-set). `FirebaseTransport`
  implements it with RTDB; `LocalTransport` implements it in memory. Practice mode and
  bots use the exact same `RoomSession` code path — bots are just players that write their
  own `inputs/{id}` — so the host logic is exercised even without a network.

## Physics and camera

* Pull strength per player is `pull × 140 pt/s²` (steady tilt) plus `55 pt/s` of velocity
  per tug burst; the rope has friction (velocity decays 1.8/s). More players = more force,
  like real tug of war; the lobby keeps teams balanced.
* Linear: the knot wins at ±250 pt.
* Circular: everyone stands on a ring-shaped ledge and holds one shared rope, so the rope is
  a zero-sum budget. You move outward while you pull harder than the average of everyone
  still standing, and inward while you pull less. Cross the inner edge and the hole swallows
  you; cross the outer edge and you drop off the ledge. Only your distance from the middle
  changes, so the arena never drifts off screen. The hole grows from five seconds in, and
  much faster after thirty, so the ledge keeps narrowing and a round always ends. The rope
  drawn through the players visibly caves in wherever somebody is losing ground.
  All constants live in `Engine/GameConfig.swift`.
* Tilt: the gravity vector from CoreMotion is turned into "how far the right edge dips" and
  "how far the top edge dips". The game projects that onto the on-screen arrow direction,
  so the rule is always *tilt toward the arrow*. A 3° dead zone, full pull at 22°, neutral
  re-captured at every countdown and on *recenter*. There's an *Invert tilt* switch in the
  profile card.
* Camera: in Linear the centre sits 55 % of the way from the centre line to your dot. In
  Circular the world rotates so your pulling direction is straight up, the hole sits below
  you and the outer pit above, and the zoom frames both edges of the ledge, so the view
  tightens as the hole grows. Position, zoom and rotation ease exponentially toward their
  targets every frame, so the view never jumps.
* Rounds are played in landscape. The game screen asks iOS for a landscape interface while
  it is on screen and releases it again on the way out; the tilt input is rotated into
  screen axes, so "tilt toward the arrow" holds however the phone is turned.

## Status

Built with Xcode 27.2 and verified in the iOS Simulator in practice mode, in light and dark
mode (both arenas, camera, eliminations, sudden death, results, rematch). Online play against another phone, AirDrop links,
tilt and NFC need real devices and a Firebase plist — see *Setup*. The original proposal
and week-10 notes are in [docs/proposal-week10.md](docs/proposal-week10.md).

## Sources and assistance

* Class weeks [09](https://github.com/molab-itp/content-2026-ima/blob/main/weeks/09_multi.md)
  and [10](https://github.com/molab-itp/content-2026-ima/blob/main/weeks/10_multi.md); the
  MoLobby / MoLobbyAnon / AnonLobbyCloud examples were read for their Firebase approach
  (anonymous sign-in, `observe(.value)` listeners, `onDisconnect`). Nothing from the class
  repos is copied into this repository.
* Firebase docs: [Realtime Database on iOS](https://firebase.google.com/docs/database/ios/start),
  [anonymous auth](https://firebase.google.com/docs/auth/ios/anonymous-auth).
* Apple docs: Core NFC, Core Motion, SwiftUI `Canvas`.
* AI assistance: this app was built with Claude Code; see [docs/ai-usage.md](docs/ai-usage.md)
  for the prompt and a summary of what it produced.
