HOA PRESIDENT - PROJECT HANDOFF SUMMARY
=======================================
Session date: 2026-10-05. Repo: /Users/sandip/Projects/hoagame (GitHub ssnanda/hoagame). Branch main.
Status of git: NOTHING from this session is committed. All changes are uncommitted working-tree edits
(per the owner's global rule: the owner verifies builds/tests and authorizes commits).

1. PROJECT OVERVIEW
-------------------
"HOA President" is a portrait mobile game (Godot 4.7, GDScript, gl_compatibility renderer, iPhone first).
You are the president of a suburban HOA: walk the subdivision, investigate complaints (allegations, not proof),
photograph evidence, decide, issue warnings/fines, do physical reinspections, run hearings, survive board politics
and annual elections. Developer: ITSpector LLC, North Carolina, USA. Community-management partner/inspiration: Wozig.
The owner gave a very long (104-section) design directive at the start of the session. Direction: polished 2D/
isometric-style gameplay with animated cinematic close-ups; keep all existing simulation depth; do not make the
Wozig portal the main gameplay; no CC&R legal-citation lookup gameplay; no full 3D.

2. CURRENT GAME / DESIGN DIRECTION
----------------------------------
- Core loop: complaint -> travel -> observe -> photograph -> decide -> warning/dismiss -> cure period ->
  physical reinspection -> hearing -> board vote -> fine/dismiss/extension -> long-term consequences.
- Fantasy: "I somehow became HOA President and must survive this neighborhood" (not an "HOA cop").
- Tone: serious administration + ridiculous suburbia; non-graphic slapstick, rare so it stays funny.
- Complaints are allegations; the UI must never reveal the answer ("Complaint", "Concern", never "VIOLATION"
  before the player establishes it).
- Pacing: complexity arrives gradually (events/board calls/legal items gated by day).

3. ARCHITECTURE AND TECHNOLOGY
------------------------------
Godot 4.7, GDScript. Autoloads: GameState, Settings, Sfx. Main scene scenes/main.tscn (scripts/main.gd orchestrator).
Key structure (pre-existing unless marked NEW):
- scripts/world/neighborhood.gd: single source of truth for geometry (streets, cul-de-sacs, lots, landmarks,
  validation, A* nav). build(seed) now takes a seed (7771 default). Minimap/full map/collision read from it.
- scripts/street.gd: street controller (input, camera, per-day state, photo capture). Child views: WorldView
  (dynamic layer), HudView, cached static chunks (StaticPainter).
- scripts/sim/: hoa_sim.gd (rules), board.gd, residents.gd, violations.gd (data-driven, data/violations.json).
  NEW: encounters.gd, weather.gd, career.gd.
- scripts/ui/: panels (case sheet scripts/case_file.gd, reinspect, hearing, vote, portal, menu_panels, ui_kit).
  NEW: encounter_panel.gd.
- NEW scripts/world/camera_input.gd: pinch/magnify/wheel zoom state (extracted from street.gd).
- Content is data-driven JSON in data/: violations, events (agenda cards), cards, branding; NEW: encounters.json,
  board_calls.json, communities.json, achievements.json.
- Rule: rendering never decides rules; simulation never draws. Static world is cached in canvas chunks;
  only people/moving vehicles/markers/weather/HUD redraw per frame.

4. FEATURES IMPLEMENTED THIS SESSION
------------------------------------
Phase 1 / HUD / input
- Pinch-to-zoom (0.6x-1.7x, smooth), trackpad magnify, mouse wheel; RESET ZOOM chip; a pinch cancels the walk
  gesture and its release cannot register as a tap. Drag release never opens a property (verified by test).
- Premature label "POSSIBLE VIOLATION OBSERVED" replaced by "SOMETHING CATCHES YOUR EYE".
- HUD declutter: compact header (DAY, SCORE, STATS, MENU). Treasury/Community/Authority bars, board mood, best
  score and version live behind a STATS toggle (button shows "STATS !" when something is critical).
- Bottom status line derived from the street's pins (e.g. "2 inspections - 1 reinspection to go" /
  "All of today's inspections are done") so it cannot contradict the "Next:" chip.
- Tap the "Next:" chip to cycle to the next open assignment (nearest first); waypoint arrow toward the objective
  when far; minimap marks reinspections in blue.
- Nearest-property selection now respects the street the player is on (no stealing prompts across roads).
Cinematic encounter system (data-driven)
- data/encounters.json: 32 scenes (trigger warning/fine/hearing/dismiss/reinspect/visit, rarity common..very_rare,
  cooldown, trait/season/relationship/"needs_favored"/"min_unfair" filters, props, lines, up to 4 choices with
  outcomes: relationship, legal, board, happiness, power, budget, score, slow).
- sim/encounters.gd picks (weighted by rarity, cooldown, filters; base chance 0.38 per ruling, 0.2 for "visit";
  no encounters on day 1). hoa_sim.pick_encounter / apply_encounter_outcome apply results once.
- ui/encounter_panel.gd: letterboxed illustrated close-up drawn in code (house front, resident figure with poses
  idle/arms_crossed/pointing/pleading/filming/yelling/shrug/laughing/waving/crying/celebrating/confused/running,
  inspector from behind, props: phone, dog, sprinklers, leafblower, neighbor, van, blanket, police, ambulance,
  inflatable, tarp, chairs, mud, mower, car), typewriter dialogue, tap to advance, SKIP, choices, shake on tension.
- Camera pushes in on the front door before the panel fades in; slow-down penalty (0.6x walking) after comic mishaps.
- Footers like "THIS MAY COME UP AT THE NEXT MEETING" really queue a board discussion next morning
  (small board/legal hit). "INSURANCE" footers charge the treasury; "ATTORNEY" footers raise legal risk.
- In headless mode the first choice is auto-applied so bots never stall.
Residents / politics
- 5 new traits: confrontational, passive_aggressive, paranoid, eccentric, forgetful (affect compliance/dispute chance,
  blurbs, matching encounters). Hostile households are reported more often.
- Selective enforcement: dismissed real violations for friends/board households are remembered (politics.favored);
  residents quote the favored name back ({favored} token).
- Board pressure calls (data/board_calls.json, 9 calls): directors phone with requests; complying is tracked by the
  enforcement ledger. Recall petition + emergency vote when 3 directors <30 support and legal >=55 (8-day cooldown).
- Hearings: 22% chance of surprise testimony that shifts case strength; board roster shown on the hearing panel.
- Election feedback is fuzzy words (board "mood" and counsel mood) rather than exact percentages.
- Legal ladder: counsel warning -> attorney letter (legal>=80) -> settlement (>=100); homeowner revolt at very low happiness.
- ARC memory: approving an architectural agenda card (arch_* with "arc" block) stores approved vs built spec; days later
  a complaint arrives from the architectural committee comparing approval to what was built.
- Vendors: landscaper/pool/irrigation quality 0-5 (events can change it). Poor landscaper -> taller grass and more
  related complaints; poor irrigation -> more dead lawn/weeds; pool quality affects summer mood.
- Insurance premium level 0-3 (policy deltas on agenda cards) charged every other day; shown in portal Finance.
- Agenda cards: events.json extended to 25+ (legal, insurance, reserve, vendor, politics). Cards gated by day.
Calendar / weather / world
- Calendar: 1 game day ~ 6.5 calendar days; HUD shows date; morning brief modal lists complaints, follow-ups,
  hearings, forecast, days to annual meeting.
- sim/weather.gd: deterministic daily weather (sunny, cloudy, rain, storm, wind, fog, hot, snow) by season weights;
  affects sky/particles/lightning, rain/wind/thunder audio, crowd size, and photo quality (rain/fog/storm penalty).
- Alive world: joggers, mail carrier, gardeners, neighbor chatters at mailboxes, contractors with ladders, visitor
  "mover" cars that drive up side streets, park at a curb, then leave; cars vary speed and pause at side-street mouths;
  a porch resident steps out (wave / ? / !) when you stand at an active property; foreground foliage corners.
- Houses: shutters, porch roofs, decks, swing sets, window glints; yards: mulch beds, driveway joints, 3 mailbox styles,
  gnomes/flags/flamingos/spinners, dead patches in summer, conifers; corner lots get hedge or picket fence + street-name post.
- Golf cart: bump thump + haptic on collision.
Progression / settings / meta
- Career (sim/career.gd, user://career.cfg): 6 communities in data/communities.json (Oak Meadow, Heritage Square,
  Brookside Townhomes, The Preserve, Ironwood Gates, Grand Lakes) with modifiers (hostility, complaints, reliability,
  dues, board bias, starting legal) and a layout seed each. Surviving 3 annual meetings completes a term, gives a
  governance rating, unlocks the next community. Starting a new term in a different community reloads the scene
  (Settings.pending_action) so the new layout is built. 8 achievements (data/achievements.json) with toasts.
- Difficulty setting (Relaxed/Standard/Hard) shifts hostility, ambiguity, cure odds, legal exposure.
- Settings: music/effects volume, text size (applies to newly built panels), zoom-out-while-walking toggle, reduce motion,
  haptics, tutorial replay, sensitivity, reset game.
- Title: Continue, New Term, Communities, Training, Settings, About. Subtitle "Run the neighborhood. Survive the meeting."
  Humorous new-game intro ("...you are now HOA President."). Training = six optional lessons. About shows ITSpector LLC,
  North Carolina, Wozig, Godot MIT attribution, privacy note. Portal footer: "Community management powered by Wozig".
- Portal: Cases tab grouped by next action (ready for reinspection / awaiting cure / hearing / disputed / fined);
  Work Orders tab lists vendor star ratings. MENU has a CASE BOARD shortcut.
- Music moods (calm/tense/absurd/triumph) via Sfx.set_mood; new sounds: rain, wind, thunder, door knock.
- Notification ladder (_notify: small/medium/important/major). Save backup (hoagame.cfg.bak) before each save;
  autosave on focus-out/close; WORLD_VERSION bumped to 8 (new fields optional on load).
- Case sheet shows a "NEXT:" line. Day-1 coaching hints improved. Evidence photos are stamped with address and date.
- Debug view (debug builds): owner/traits/relationship/case state labels, violation slot ids, walker routes, objective line.

5. FILES CREATED / MODIFIED
---------------------------
NEW: data/encounters.json, data/board_calls.json, data/communities.json, data/achievements.json,
scripts/sim/encounters.gd, scripts/sim/weather.gd, scripts/sim/career.gd, scripts/ui/encounter_panel.gd,
scripts/world/camera_input.gd, tools/encounter_test.gd, tools/qa_encounters.gd/.tscn, tools/qa_input.gd/.tscn,
tools/shots.gd/.tscn, CHAT_HANDOFF_SUMMARY.txt, progress.md.
MODIFIED: README.md, data/branding.json, data/events.json, scripts/game_state.gd, scripts/main.gd,
scripts/settings.gd, scripts/sfx.gd, scripts/street.gd, scripts/sim/hoa_sim.gd, scripts/sim/residents.gd,
scripts/sim/board.gd, scripts/ui/{hearing_panel,menu_panels,ui_kit,portal_panel}.gd, scripts/case_file.gd,
scripts/world/{ambient,house_painter,hud_view,neighborhood,player_controller,static_painter,world_view}.gd,
tools/validate_world.gd.

6. IMPORTANT CLASSES / FUNCTIONS
--------------------------------
- main.gd: _play_encounter(house, trigger), _maybe_board_call, _daily_brief, _show_term_complete, _run_meeting(votes,title),
  _notify, _award, _open_communities, _begin (community reload logic), _next_step_text, _update_task, _update_hint.
- hoa_sim.gd: new_term(community), pick_encounter, apply_encounter_outcome, favored_name/_note_favored, register_arc,
  _arc_assignments, pick_board_call/apply_board_call, apply_vendor/apply_policy, _recall_due, _vendor_biased, build_hearing twist.
- street.gd: begin_cinematic/end_cinematic, apply_slow, cycle_objective, zoom_input (CameraInput), world_seed.
- neighborhood.gd: build(seed_value), validate() (now also "house faces away from its street").
- ambient.gd: movers, gardeners, talkers, joggers/mail carrier, contractor crews, mover_pose.

7. GAMEPLAY MECHANICS (summary)
-------------------------------
Rulings: dismiss/warning/hearing/fine with rules from ruling_options (fine needs prior notice or severe violation and
usable evidence). Warnings have cure periods and create physical reinspection assignments. Hearings: player recommends,
five directors with priorities vote and can overrule. Annual meeting every 10 game days. Legal risk, board support and
the enforcement-consistency ledger drive consequences. Encounters resolve outcomes once.

8. UI/UX DECISIONS
------------------
Neighborhood dominates the screen; secondary info is behind STATS. Concise contextual choices instead of dialogue trees.
Touch targets >=48px; iOS safe-area handling in main._apply_safe_area. Modals sized to content. No giant modal spam:
use the notification ladder. Terse admin copy.

9. ART / GRAPHICS DIRECTION
---------------------------
Polished stylized top-down/tilted look drawn entirely in code (no art assets): cached lot chunks with shadows, houses,
yards, trees; code-drawn cinematic close-ups; seasonal tints/particles; weather overlays. No paid assets.

10. DECISIONS EXPLICITLY APPROVED / INSTRUCTED BY THE OWNER
-----------------------------------------------------------
- Keep all existing systems; adapt rather than rebuild; implement, don't just plan.
- Complete the WHOLE 104-section list; do not ask permission for obvious fixes; do visual testing myself.
- Headless/off-screen running is acceptable for tests (owner asked if possible; an off-screen window works).
- No paid dependencies; no real device camera; evidence is in-game screenshots only.

11. REJECTED / DEFERRED (from the owner's directive)
----------------------------------------------------
Rejected as pillars: portal as main gameplay; elaborate enterprise HOA portal; CC&R citation lookup; full 3D.
Deferred: distinct art/amenities per community beyond layout seed; richer traffic turning; more vendors; real parallax.

12. KNOWN ISSUES / LIMITATIONS
------------------------------
- Not built/finished: unique art/amenities/violation mixes per community; cars do not turn or use driveways;
  street characters have only simple animations (rich poses exist only in close-ups); towing/management vendors are cards only;
  special assessments are a card; music is four generated pads; no true parallax; golf cart has no parking/driving interactions.
- Audio was never listened to; no on-device (iPhone) testing was possible. macOS desktop shows an extra top gap
  from the display safe area that iOS code handles differently.
- Text-size setting applies only to panels created after the change.
- Community change triggers a scene reload (untested on a real device).
- Smoke runs reached at most day ~31; term-complete screen was verified only by a forced call, not a natural bot run.
- A lost ARC approval is possible if its reinspection assignment collides the same day (minor).
- Nothing is committed.

13. TODO / NEXT STEPS
---------------------
1) Commit after the owner verifies. 2) Give each community distinct visuals, amenities, violation weights and board culture.
3) Cars that turn/enter driveways; street-level resident animations (run, fall, cry). 4) Real vendor/legal systems
(towing, management company, special assessment, lawsuits). 5) Richer music and a real audio pass. 6) Parallax/depth.
7) On-device iPhone QA (safe areas, haptics, pinch on hardware). 8) Cart parking/drive interactions.

14. HOW TO RUN / TEST
---------------------
Godot at /Applications/Godot.app/Contents/MacOS/Godot (referred to as godot below).
- Play: godot --path .
- Layout validation: godot --headless --path . --script res://tools/validate_world.gd   (add: -- seeds=25 for a sweep)
- Encounter catalog/rarity: godot --headless --path . --script res://tools/encounter_test.gd
- Encounter flow QA: godot --headless --path . res://tools/qa_encounters.tscn
- Bot playthroughs (run in a throwaway copy; writes the save slot; use HOME=<scratch>):
  godot --headless --path . res://tools/smoke_test.tscn -- bot=smart|random|fine_all|dismiss_all [seed=N]
- Visual QA (needs renderer; off-screen window works): HOME=<scratch> godot --path . --position 6000,6000
  --resolution 540x960 res://tools/shots.tscn -- out=<dir> [shots=street,encounters,menus,maps,flow,life]
- Input QA: godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_input.tscn
- Last results this session: 30-seed layout sweep 0 warnings; 32 encounters 0 problems; input QA 0 problems;
  smart-bot 28 days 0 errors.
- Note: `godot --script` cannot compile scripts that reference autoload names (Settings/Sfx/GameState); use .tscn tools.

15. CONVENTIONS TO PRESERVE
---------------------------
- Owner's global rules: do not commit/push/merge; do not run builds/Docker/installs unless asked; never delete files
  (move to macOS Trash via Finder); never bump versions; summarize changes + root cause + manual verification commands.
- Complaints are allegations; never leak the answer in labels/colors.
- Content goes in data/*.json (new violation/encounter/call/community = new JSON entry, no code).
- Keep rendering separate from rules; keep the single geometry source (Neighborhood) for map/minimap/validation.
- Seeds: Neighborhood.build(seed) and sim `-- seed=N` for reproducibility.
- Keep saves backward compatible (new fields optional; WORLD_VERSION constant in main.gd).
- Do not change bundle IDs/signing; customer-facing branding is ITSpector LLC (NC, USA) and Wozig.
