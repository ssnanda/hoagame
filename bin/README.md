# bin/

Build scripts for **HOA President** (`ssnanda/hoagame`, Godot 4 → iOS).

## Order

| step | script | purpose | output |
|---|---|---|---|
| 1 | `1-bump-version.sh` | next version → `VERSION`, `project.godot`, `export_presets.cfg` → commit `Release HOA President X.Y.Z` | — |
| 2a | `2a-hoagame-ipa.sh` | bump menu → commit → export IPA with Godot → push → publish ios-latest | `~/Documents/GitHub/ipa/hoagame.ipa` |
| 2b | `2b-sim-iphone.sh` | export Xcode project → build → install + launch in iPhone simulator | simulator app |
| 3 | `3-device-run.sh` | install the IPA from 2a on a connected iPhone | app on device |

2a and 2b are peers: run either after step 1. 2a includes step 1 (it shows the same menu),
so you only run 1 by hand for a bump without building. 2b never bumps.

## Usage

```bash
./bin/1-bump-version.sh     # menu → bump → commit → push
./bin/2a-hoagame-ipa.sh     # menu → bump → commit → build IPA → push → publish ios-latest + altstore.json
./bin/2b-sim-iphone.sh      # build + run in simulator
./bin/3-device-run.sh       # install the IPA on the connected iPhone
```

No parameters needed. Opt-outs: `2a --no-push`, `2a --no-publish`, `1 --no-push`.

One-time: Godot › Editor › Manage Export Templates › Download.
