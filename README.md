# HOA President

Run the neighborhood. Survive the board.

A portrait mobile game (Godot 4, GDScript, iPhone first). You are the president of a
suburban HOA. Walk the subdivision, investigate complaints, photograph evidence, decide
what is actually a violation, and live with the consequences. Satire on top,
a surprisingly deep simulation underneath.

Developed by **ITSpector LLC** (North Carolina, USA). Community management partner and
inspiration: **Wozig**.

## The loop

Complaint → travel → observe → investigate → photograph → decide → consequence → follow-up.

- **Complaints are not proof.** Each has a source with a reliability (a frequent filer is
  wrong more often than a Wozig management inspection). Some are false; some are borderline.
- **Evidence matters.** The camera scores framing, distance, zoom, lighting and trees in the
  way. It records what a photo *shows* ("Evidence recorded: vehicle on lawn"), never
  marking the answer in advance.
- **Rulings follow the HOA process.** Dismiss, warn, schedule a hearing or fine. A fine needs
  a prior notice (or a severe violation) and usable evidence.
- **Follow-ups are physical.** Warnings have cure periods. When one ends you get a
  *reinspection* assignment and must walk back: fixed, partly fixed, unchanged or worse.
  Unresolved cases go to a board hearing where you make the recommendation and five board
  members with their own priorities vote.
- **Politics.** Board support, legal risk (including selective enforcement) and an annual
  meeting every ten days decide whether you keep your seat.
- **Seasons.** Spring tulips and rain, summer sprinklers and pool swimmers, fall leaf piles
  and leaf blowers, winter snow caps and holiday lights. Violations follow the calendar
  (no tall grass under snow).
- **Cinematic encounters.** After a ruling the camera pushes in on the front door and a
  letterboxed close-up plays: the resident comes out, you pick a concise reply, and the
  outcome (relationship, legal risk, board support, a temporary slowdown) applies once.
  Scenes are data in `data/encounters.json` (trigger, rarity, cooldown, trait/season
  filters, props, lines, choices); adding one needs no code. Common scenes are everyday
  explanations; the very rare slapstick one is cartoon-only and non-graphic.
- **Board pressure.** Directors phone with requests (fine a critic, overlook a friend, delay a
  vendor). Compliance is tempting and is tracked by the selective-enforcement ledger.
  Three angry directors plus legal exposure can trigger a recall petition and an emergency vote.
  Calls live in `data/board_calls.json`.
- **ARC memory.** Approving an architectural request is remembered; days later the committee
  reports what was actually built and you inspect the work against the approval.
- **Weather and calendar.** Deterministic daily weather (sunny, cloudy, rain, thunderstorms,
  wind, fog, heat, snow) changes the sky, ambience, crowds and photo quality. A game day stands
  for about a week of calendar time; each morning opens with a short brief.
- **Career.** Surviving three annual meetings completes a term, rates your governance and
  unlocks the next of six communities (`data/communities.json`, modifiers only for now), with
  achievements in `data/achievements.json`. Stored in `user://career.cfg`.
- **Zoom.** Pinch (or mouse wheel / trackpad) zooms the neighborhood; RESET ZOOM appears
  when you are off the default.
- **Wozig portal.** Overview with enforcement balance by group, cases, board, finance
  ledger, violation history, resident directory, work orders and agenda decisions.
- **Audio.** Procedural sounds and ambience layers (traffic, cart, leaf blower, sprinklers,
  birds, dogs, board murmur). iOS audio uses the Ambient session, so the silent switch is
  respected; sound, music and haptics have separate settings.

## Running

Open the folder in Godot 4.7 and press play, or run on a device with the scripts in `bin/`.

```bash
./bin/1-bump-version.sh     # next version → VERSION, project.godot, export_presets.cfg → commit → push
./bin/2a-hoagame-ipa.sh     # build IPA, push, update altstore.json, publish a versioned release
./bin/2b-sim-iphone.sh      # build + run in the iPhone simulator
```

Developer tools (run in a throwaway copy of the project; the smoke test writes the save slot):

```bash
godot --headless --path . --script res://tools/validate_world.gd   # layout validation
godot --headless --path . --script res://tools/encounter_test.gd   # encounter catalog + rarity sampling
godot --headless --path . res://tools/qa_encounters.tscn            # every scene x every choice plays cleanly, finishes once
godot --headless --path . --script res://tools/validate_world.gd -- seeds=25   # layout sweep across seeds
# Visual + input QA need a real renderer; an off-screen window works (nothing appears on your screen):
godot --path . --position 6000,6000 --resolution 540x960 res://tools/shots.tscn -- out=/some/dir [shots=street,encounters,menus,maps,flow,life]
godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_input.tscn   # drag release, tap, pinch
godot --headless --path . res://tools/smoke_test.tscn -- bot=smart seed=7       # reproducible session (seed=N)
godot --headless --path . res://tools/smoke_test.tscn -- bot=smart # plays whole terms; bot=random|smart|fine_all|dismiss_all
```

In a debug build, MENU → DEBUG VIEW overlays lot polygons, house footprints, driveways, the
inspection radius, violation slots and property ids. World validation prints at startup.

## QA checklist (sections 91-96)

Automated: `validate_world` (overlaps, driveways, mailboxes, facing, reachability, slots, seeds),
`qa_encounters` (start, all lines, every choice, outcome applied once), `smoke_test` bots
(`smart|random|fine_all|dismiss_all`) for cases, reinspections, hearings, elections.
By hand on a device: pinch zoom and drag release, cul-de-sacs, narrow sidewalks, golf cart
bumps, evidence camera on wrong/partial/duplicate framing, a full warning -> cure ->
reinspection -> hearing loop, a recall, a term completion, and a save/quit/resume cycle.

## Performance model

The street is drawn in two layers. The **static world** (ground, roads, street furniture,
every lot with its house, yard objects and trees) is recorded once per day/season into
cached canvas chunks (`world_chunk.gd`, one per lot) and the camera is just a transform on
their root node; time of day is a tint on it. Only people, moving vehicles, markers,
weather and the HUD are redrawn each frame. Stale chunks near the camera are redrawn a
few per frame (more while a panel covers the street) so a new day never hitches.

Measured on a 2019 MacBook Pro (AMD Radeon Pro 5500M), steady state while walking the
avenue: ~7 ms per frame, with ~1.5 ms of that in GDScript. Before the chunk cache the
world draw alone cost 45-65 ms. `street.perf` exposes smoothed process/world/HUD
microseconds for tuning.

## Architecture

```
scripts/
  main.gd              orchestrator: HUD, day loop, panels, saving
  street.gd            street controller: input, camera follow, per-day state, photo capture
  game_state.gd        autoload: stats, deck, score, seasons/weekdays
  settings.gd, sfx.gd  autoloads: preferences; small procedural sounds (no asset files)
  case_file.gd         the case sheet panel
  lawn_game.gd         lawn measurement tool
  world/
    neighborhood.gd    SINGLE SOURCE OF TRUTH: streets, cul-de-sacs, lots, landmarks, validation
    lot.gd             one property: geometry, driveway, mailbox, address
    lot_slots.gd       where each violation object sits on a lot (lot-local frame)
    player_controller.gd  walking / golf cart movement and collision
    ambient.gd         walkers, traffic, trucks, crews, kids, parked cars
    evidence_camera.gd framing quality, what a photo documents, multi-photo album
    static_painter.gd  everything that holds still, drawn into cached chunks (world_chunk.gd)
    world_view.gd      dynamic layer: people, vehicles, markers, weather; owns the chunks
    house_painter / object_painter / actor_painter / draw_util   shared drawing code
    hud_view.gd        mobile HUD, camera frame, minimap, full map, album
    debug_overlay.gd   geometry debug drawing
  sim/
    hoa_sim.gd         rules: assignments, rulings, cure/reinspection/hearing/fine, discovery
    encounters.gd      cinematic encounter picker and outcomes (data/encounters.json)
    weather.gd         deterministic daily weather and its modifiers
    career.gd          communities, unlocks, achievements (user://career.cfg)
    violations.gd      data-driven catalog + complaint generation (data/violations.json)
    residents.gd       households: traits, relationship score, memory
    board.gd           board characters, votes, election, legal risk, selective enforcement
  ui/                  shared kit + reinspection, hearing, vote, portal and menu panels
data/
  violations.json      every violation: category, severity, cure period, fines, evidence, texts
  events.json, cards.json   agenda cards and neighborhood drama
  branding.json        title, developer, partner and link placeholders
```

Rules of the road:

- The minimap and full map draw from `Neighborhood` data. There is no second copy of the
  road geometry.
- Rendering never decides rules; the simulation never draws.
- Violation definitions, fines and complaint texts live in `data/`, not in code.

## Save format

`user://hoagame.cfg` holds the run; `user://settings.cfg` holds preferences (kept separate so
resetting a game never wipes them).

The run stores day, score, stats, streak, deck and a `world` dictionary with a
`world_version`:

| version | change |
|---|---|
| ≤5 | original grid neighborhood |
| 6 | neighborhood rebuilt; lot ids no longer match older saves |
| 7 | simulation split out: residents with traits/relationships, case records with cited ids, assignments with sources, reinspection results, board members as characters, golf cart state, multi-photo evidence |

Loading an older save migrates it: version <6 keeps day/score/stats and starts a fresh
neighborhood day; version 6 gets residents, board and evidence upgraded in place
(`Residents.migrate`, `Board.migrate`, `EvidenceCamera.load_saved`).

## Privacy

Evidence photos are game-generated screenshots stored in the app's own sandbox. The game does
not use the device camera, upload photos or collect analytics.

## Release notes for maintainers

- Bundle identifiers and signing are unchanged. Customer-facing developer name is ITSpector LLC
  (AltStore metadata); the bundle id stays `com.ssnanda.hoagame`.
- iOS 27-only APIs are not used: the installed Xcode SDK was 26.5 when this was written.
  Layout is driven by the display safe area and a width-fixed, height-expanding stretch, so
  taller iPhones (Pro Max sizes) need no code change; verified at 414x896 and 720x1280.
- Godot writes a `.uid` file next to each script. Commit them (the repo already tracks them).
- `tools/` is excluded from exported builds.
