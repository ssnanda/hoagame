# bin/

Build scripts for **HOA President** (`ssnanda/hoagame`, Godot 4 → iOS).

## Order

| step | script | purpose | output |
|---|---|---|---|
| 1 | `1-bump-version.sh` | next version → `VERSION`, `project.godot`, `export_presets.cfg` → commit `Release HOA President X.Y.Z` | — |
| 2a | `2a-hoagame-ipa.sh` | optionally bump → export IPA → push → update AltStore source → publish an immutable versioned release | `~/Documents/GitHub/ipa/hoagame.ipa` |
| 2b | `2b-sim-iphone.sh` | export Xcode project → build → install + launch in iPhone simulator | simulator app |

2a and 2b are peers. On a clean tree, 2a builds the current version. With uncommitted
changes or an explicit `--bump`, it runs step 1 first. 2b never bumps.

## Usage

```bash
./bin/1-bump-version.sh     # menu → bump → commit → push
./bin/2a-hoagame-ipa.sh     # build, push, update source, publish versioned IPA
./bin/2a-hoagame-ipa.sh --bump patch
./bin/2a-hoagame-ipa.sh --local     # local build only
./bin/2b-sim-iphone.sh      # build + run in simulator
```

Publishing is the default. Each build uses a versioned tag such as
`ios-0.1.21-22`, so a cached AltStore source cannot download the wrong IPA.
Use `2a --local` for a local-only build or `2a --no-publish` to push without
publishing a release.

One-time: Godot › Editor › Manage Export Templates › Download.
