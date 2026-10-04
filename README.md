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
godot --headless --path . res://tools/smoke_test.tscn -- bot=smart # plays whole terms; bot=random|smart|fine_all|dismiss_all
```

In a debug build, MENU → DEBUG VIEW overlays lot polygons, house footprints, driveways, the
inspection radius, violation slots and property ids. World validation prints at startup.

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
    world_view.gd      draws the world; house_painter / object_painter / actor_painter / draw_util
    hud_view.gd        mobile HUD, camera frame, minimap, full map, album
    debug_overlay.gd   geometry debug drawing
  sim/
    hoa_sim.gd         rules: assignments, rulings, cure/reinspection/hearing/fine, discovery
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
