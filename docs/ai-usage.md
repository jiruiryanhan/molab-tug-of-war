# AI usage

This project was built with **Claude Code** (model: Claude Fable 5.1) on 13 Nov 2026,
working directly in this repository on the branch `feature/tug-of-war-app`. This file is the
record of what was asked and what the AI produced. Add to it whenever AI is used again.

## Session 1 — 13 Nov 2026

### My prompt (verbatim)

> https://github.com/jiruiryanhan/molab-tug-of-war  this is my repo (change it how every you like)
>
> read this, make it. AI usage is fine as long as documented (my prompt and output(summary), need a ai-usage.md)
>
> write in swift, make the real time tug of war, two mode: team-linear: people join the teams (or join room then split randomly), join using code, airdrop link, or apple NFC. team-circular: circular tied tug, drag your opponents into the hole in the middle to eliminate them, team (randomly place on the circle) or individual, last standing wins, join using code, airdrop link, or apple NFC.
>
> each player is a round dot, with color boarder, and profile pic in the center, if no profile pic then name initials
>
> view: always somewhat centered on your player(avatar, round dot), camera can pan and shift around based on the coordinates, should always see the center line or center hole. make the shift smooth.
>
> https://github.com/molab-itp/content-2026-ima/blob/main/weeks/09_multi.md
> https://github.com/molab-itp/content-2026-ima/blob/main/weeks/10_multi.md
> use multiuser methods similar to these repos, class material DO NOT FORK, COPY, OR DISTRIBUTE. DO NOT MODIFY THEM. READ ONLY
>
> let me know what you need. questions?

Two sketches were attached: "Frame 1" (linear: red dots left, blue dots right, a dotted
centre line, the red half tinted, an arrow labelled "← TUG!") and "Frame 19" (circular:
red and blue dots alternating around an arc of rope with a black hole below, "TUG!" arrow
pointing away from the hole).

### What the AI read (read-only, nothing copied)

* The two class pages above, the existing README/proposal in this repo.
* Class example code, to match the multiuser approach: `98-MoGallery` (MoLobby and
  MoLobbyAnon lobby models, `UserModel`), `09-AnonLobbyCloud` (anonymous auth, store
  listeners), and the Firebase SDK versions pinned in their `Package.resolved`.
* Firebase iOS SDK release notes (to pick a current version that builds on Xcode 27).

### What the AI produced

* A complete Xcode project (`TugOfWar.xcodeproj`, synchronized source folder, Firebase
  13.x via Swift Package Manager) and about 2,700 lines of Swift:
  * **Models** for room metadata, players, inputs, simulation state, local profile.
  * **GameEngine** — host-authoritative physics for both arenas (steady pull + tug
    impulses, friction, eliminations, sudden-death hole growth, win checks). The circular
    arena went through two designs: first a rigid ring that shifts with the net pull, which
    simulator runs showed could only ever eliminate the player directly opposite the pull
    (rounds stalled after the first elimination); it was replaced by a knot-and-rope model
    where every player's rope runs to one central knot and whoever gets dragged too far
    falls in. Constants were tuned from timed simulator runs (knot spring, sudden death).
  * **Camera** — smooth pan/zoom/rotate that keeps your dot and the centre line / hole in
    view; the circular arena rotates so your pull direction is "up".
  * **RoomTransport** abstraction with a Firebase Realtime Database implementation
    (anonymous auth, `observe(.value)`, `onDisconnect`, transactions for host hand-over)
    and an in-memory implementation used for offline practice and bots.
  * **RoomSession** — lobby, team assignment / random seating, countdown, host simulation
    loop publishing ~12×/s, client interpolation, throttled input sending, host migration.
  * **Input** — CoreMotion tilt ("tilt toward the arrow", calibrated neutral, dead zone,
    invert switch), swipe-to-tug, tap, and a TUG! button.
  * **Joining** — 4-letter codes, `tugofwar://join/CODE` URL scheme (ShareLink → AirDrop),
    Core NFC tag reading and writing.
  * **Views** — home/profile (name, photo picker, tiny base64 avatar), create-room sheet,
    lobby (code, share, NFC write, team switching, start), game canvas (dots with photo or
    initials, rope, knot, goal lines, hole, TUG! arrow, fall-in animation), HUD, results.
  * `database.rules.json`, `.gitignore` (keeps `GoogleService-Info.plist` out of git), app
    icon, this file and the README.
* Design decisions the AI made and flagged in the README: Realtime Database instead of
  Firestore (the class lobby already uses it and it suits ~10 Hz updates); the class pins
  Firebase 9.6.0 from 2022, which does not build on Xcode 27, so 13.x is used; one phone
  (the host) simulates and others interpolate; photos are stored as ~5 KB base64 thumbnails
  in the player record instead of Firebase Storage; NFC is in-app tag scan/write (iPhones
  cannot act as tags for each other).

### What was verified, and what was not

* Verified by the AI in the iOS Simulator (Xcode 27.2, iPhone 17 / iOS 27): the app builds
  with no warnings from its own sources; practice mode runs both arenas against bots via
  the debug launch flags; camera behaviour, countdown, eliminations, sudden death, results
  overlay. The AI also ran an independent multi-agent code review (five reviewers by
  subsystem, each finding cross-examined by three skeptical verifiers). Fourteen defects
  survived and were fixed in the second commit: tug counters replaying after a reconnect,
  a dropped phone rejoining with a stale seat, a host that kept publishing while offline,
  an optimistic host claim, a List row that fired both lobby buttons, tilt math that broke
  when the phone was held flat, NFC re-entry, overlapping joins, the generic "iPhone"
  default name, and a sudden-death hole that could never reach the players.
* Not verified (needs real devices and a Firebase plist, which is intentionally not in the
  repo): online play between phones, AirDrop link hand-off, tilt feel, NFC read/write.
  The multiplayer code path is the same one practice mode exercises, but network timing
  and Firebase rules have not been exercised yet.

### My part

* Concept, the two sketches, the proposal and weekly plan (`docs/proposal-week10.md`).
* Reviewing the result, testing on real phones, tuning the constants in
  `Engine/GameConfig.swift`, and whatever changes come after this commit.

## Session 2 — 19 Nov 2026

### My prompt (verbatim)

> 我觉得最好还是用苹果原生的 UI 吧。我们不要自己设计 UI，直接用 Xcode、Swift 那些东西，界面可以做得很简单、很干净，都用苹果的界面风格
>
> 做好之后Merge to main

(In English: use Apple's native UI instead of a custom-designed one — keep it simple and
clean, in Apple's own interface style — then merge to main.)

### What the AI produced

* Rebuilt every screen out of standard SwiftUI controls, with no hand-made cards,
  materials or fixed-size fonts:
  * **Home** is a `Form`: a player section (dot, name field, `PhotosPicker`, tilt toggle),
    a "Play with Friends" section (create, room-code field, join, NFC scan) whose footer
    carries the connection state, a practice section, and a "How to Play" section.
  * **New Room** is a `Form` sheet with an inline `Picker` for the arena, a segmented
    picker for teams, a `Stepper` for bots, and Cancel / Create in the toolbar.
  * **Lobby** is a `List` with the room code (selectable), `ShareLink`, copy and NFC rows,
    player sections, and a Start Round button.
  * **Game** is a `NavigationStack` with a real toolbar (leave, room code, score), the
    rope position as a native `Gauge`, the pull strength as a `ProgressView`, and the
    controls in a `.bar`-backed bottom inset. The field is laid out inside the safe area,
    so the camera no longer centres on pixels hidden behind the bars.
  * **Results** is a half-height sheet with `presentationDetents` and background
    interaction, so the final field stays visible behind it.
* Switched all colours to system colours (`.red`, `.blue`, `Color(.systemBackground)`,
  `.primary`, `.secondary`), so the whole app, the drawn field included, works in dark
  mode; set the accent colour to the system blue; redrew the app icon in system colours
  and without an alpha channel.
* Text is now Dynamic Type styles rather than fixed point sizes, and the dots, meters and
  toolbar items carry accessibility labels.

### What was verified

* Builds clean on Xcode 27.2, and practice rounds were run in the iOS Simulator in both
  light and dark mode (home, lobby, both arenas, sudden death, results).
* Still unverified: online play, AirDrop links, tilt and NFC, which need real phones and a
  Firebase config file.

## Session 3 — 19 Nov 2026

### My prompt (verbatim)

> 我看现在你这个 demo，提几点想法：
>
> 1. 屏幕方向：我希望这个游戏玩的时候是横屏的，需要把手机横过来才能玩。
> 2. 活动范围与机制：我觉得你现在这个球的可活动范围太小了。你看它一直在顶着边往顶上挤、往顶上拉。最后一般很多都剩下一个红、一个蓝。
> 3. 场景与玩法建议：我希望能做成中间是一个不断扩大的洞，外圈也是坑（都是黑的）。这就相当于是在一个圆环上拔河：中间有个洞，外面也是边界，掉出界就完了，两边同样都是坑

(In English: play rounds in landscape; the play area is too small and the ring keeps jamming
against the top edge, with rounds ending one red against one blue; make the circular arena a
ring-shaped ledge with a growing hole in the middle and a pit outside, both black, so going
over either edge puts you out.)

### What the AI produced

* **Landscape.** The app now allows portrait and both landscape orientations, and the game
  screen asks iOS for landscape while it is on screen (an app delegate holds the allowed
  mask, `requestGeometryUpdate` performs the rotation) and releases it on the way out. The
  lobby says a round is played sideways. The game HUD has a compact layout for landscape:
  one row with the pull meter, the TUG! button and recenter.
* **Orientation-aware tilt.** Device roll and pitch are rotated into screen axes from the
  window scene's interface orientation, so "tilt toward the arrow" still holds with the
  phone turned.
* **The circular arena was rebuilt.** The old version moved one central knot and dragged
  players off fixed spots, which made the whole ring translate (that is what kept pressing
  against the top edge) and could only ever eliminate the player opposite the pull. Now the
  arena is a ring-shaped ledge: a hole in the middle that grows all round, a pit outside,
  and one shared rope. A player only moves along their radius, outward while they pull
  harder than the average of everyone still standing and inward while they pull less, so
  the rope is a zero-sum budget and both edges are lethal. Nothing translates any more, so
  the arena cannot drift off screen.
* **More room to move.** Dots, rope spacing and the arena are larger, and the camera frames
  both edges of the ledge and tightens as the hole grows.
* Bots learned to read the ledge: they dig in near the hole, ease off near the outer edge,
  and each one prefers its own standing distance so the field spreads out and the hole
  catches the hindmost instead of everyone at once.
* Tuning came from timed simulator runs: the first radial physics threw a player who held
  full pull off the outer edge in about two seconds, so the force was softened and the
  damping raised.

### What was verified

* Builds clean; rounds were run in the iOS Simulator in landscape, in light and dark mode,
  for both arenas and both circular team modes: the countdown, the growing hole, falling in
  at either edge, sudden death, results and rematch.
* Still unverified: online play, AirDrop links, tilt and NFC, which need real phones and a
  Firebase config file. The landscape tilt mapping in particular has not been felt on a
  real device.

