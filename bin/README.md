# bin/

Build scripts for **HOA President** (`ssnanda/hoagame`, Godot 4 → iOS).

## Order

| step | script | purpose | output |
|---|---|---|---|
| 1 | `1-bump-version.sh` | next version → `VERSION`, `project.godot`, `export_presets.cfg` → commit `Release HOA President X.Y.Z` | — |
| 2a | `2a-hoagame-ipa.sh` | optionally bump → export IPA with Godot → save locally; push/publish only when requested | `~/Documents/GitHub/ipa/hoagame.ipa` |
| 2b | `2b-sim-iphone.sh` | export Xcode project → build → install + launch in iPhone simulator | simulator app |

2a and 2b are peers. On a clean tree, 2a builds the current version. With uncommitted
changes or an explicit `--bump`, it runs step 1 first. 2b never bumps.

## Usage

```bash
./bin/1-bump-version.sh     # menu → bump → commit → push
./bin/2a-hoagame-ipa.sh     # build current IPA locally (no push or publish)
./bin/2a-hoagame-ipa.sh --bump patch
./bin/2a-hoagame-ipa.sh --bump patch --publish
./bin/2b-sim-iphone.sh      # build + run in simulator
```

`2a --push` pushes after a successful build. `2a --publish` also refreshes the rolling
`ios-latest` release and `altstore.json`.

One-time: Godot › Editor › Manage Export Templates › Download.
