#!/usr/bin/env bash
set -euo pipefail

# HOA President — iOS IPA builder (+ optional publish)
# ----------------------------------------------------
# Exports a development-signed IPA with Godot (headless) and moves it to
# ~/Documents/GitHub/ipa/hoagame.ipa.
#
# Version bumping lives in bin/1-bump-version.sh. This script calls it when the
# working tree has uncommitted changes (or with --bump/--version/--no-bump).
# By default it builds and saves the IPA locally without pushing or publishing.
# Add --push to push the branch, or --publish to push and refresh ios-latest.
#
# Common runs:
#   ./bin/2a-hoagame-ipa.sh
#   ./bin/2a-hoagame-ipa.sh --bump patch
#   ./bin/2a-hoagame-ipa.sh --bump patch --publish

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PRESET_NAME="iOS"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="HOA President"
BUNDLE_ID="com.ssnanda.hoagame"
IPA_OUTPUT_DIR="$HOME/Documents/GitHub/ipa"
IPA_BUILD_DIR="$ROOT_DIR/build/ios"
IPA_BUILD_PATH="$IPA_BUILD_DIR/hoagame.ipa"
IPA_FINAL_PATH="$IPA_OUTPUT_DIR/hoagame.ipa"
GITHUB_REPO="ssnanda/hoagame"
RELEASE_TAG="ios-latest"
RELEASE_TITLE="HOA President — iOS (latest)"

ALTSTORE_MANIFEST="$ROOT_DIR/altstore.json"
ALTSTORE_BRANCH="main"
ALTSTORE_SOURCE_ID="com.ssnanda.hoagame.altstore"
ALTSTORE_SOURCE_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$ALTSTORE_BRANCH/altstore.json"
ALTSTORE_ICON_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$ALTSTORE_BRANCH/icon.png"
ALTSTORE_MIN_IOS="13.0"

GIT_COMMIT="true"
GIT_PUSH="false"
GITHUB_RELEASE="false"
DELETE_ONLY="false"

usage() {
  cat <<'USAGE'
HOA President — iOS IPA builder (Godot export).

Usage:
  ./bin/2a-hoagame-ipa.sh [options]

Options:
  --version X.Y.Z+B     Force a version (passed to 1-bump-version.sh)
  --bump patch|minor|major|build
  --no-bump             Build the current version, don't bump
  --delete              Delete the local IPA and exit (no build)
  --repo OWNER/REPO     Override GitHub repo (default: ssnanda/hoagame)
  --push                Push the branch after building
  --publish             Push + refresh ios-latest and altstore.json
  --no-git-commit       Rewrite version files only, don't commit the bump
  --help

Env:
  GODOT=/path/to/Godot  (default /Applications/Godot.app/Contents/MacOS/Godot)

Default: bump only when the tree is dirty, then build and save the IPA locally.
One-time setup: Godot > Editor > Manage Export Templates > Download.
USAGE
}

get_version() { [[ -f "$VERSION_FILE" ]] && tr -d '[:space:]' < "$VERSION_FILE"; }

validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || {
    echo "Error: version must use X.Y.Z+B format, example 1.0.0+1" >&2
    exit 1
  }
}

require_files() {
  [[ -f "$VERSION_FILE" ]] || { echo "Error: missing VERSION" >&2; exit 1; }
  [[ -f "$ROOT_DIR/export_presets.cfg" ]] || { echo "Error: missing export_presets.cfg" >&2; exit 1; }
  [[ -x "$BIN_DIR/1-bump-version.sh" ]] || { echo "Error: missing bin/1-bump-version.sh" >&2; exit 1; }
  [[ -x "$GODOT" ]] || { echo "Error: Godot not found at $GODOT (set GODOT=...)" >&2; exit 1; }
}

require_git() {
  command -v git >/dev/null 2>&1 || { echo "Error: git command is required" >&2; exit 1; }
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: $ROOT_DIR is not a git repository" >&2
    exit 1
  }
}

require_gh() {
  command -v gh >/dev/null 2>&1 || {
    echo "Error: GitHub CLI required for --publish. 'brew install gh' or drop --publish." >&2
    exit 1
  }
  gh auth status >/dev/null 2>&1 || { echo "Error: run 'gh auth login'." >&2; exit 1; }
}

working_tree_dirty() { [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; }

git_sync_branch() {
  cd "$ROOT_DIR"
  local branch; branch="$(git rev-parse --abbrev-ref HEAD)"
  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "Git: syncing $branch with origin (pull --rebase)..."
    git pull --rebase origin "$branch" || \
      echo "Warning: pull --rebase failed — continuing with local state." >&2
  fi
}

git_push_branch() {
  cd "$ROOT_DIR"
  local branch; branch="$(git rev-parse --abbrev-ref HEAD)"
  git push -u origin "$branch"
  echo "Git: pushed $branch"
}

delete_old_ipa() {
  [[ -f "$IPA_FINAL_PATH" ]] && { echo "Deleting old IPA: $IPA_FINAL_PATH"; rm -f "$IPA_FINAL_PATH"; }
  return 0
}

build_ipa() {
  echo ""
  echo "Exporting IPA with Godot..."
  rm -rf "$IPA_BUILD_DIR"
  mkdir -p "$IPA_BUILD_DIR" "$IPA_OUTPUT_DIR"
  "$GODOT" --headless --path "$ROOT_DIR" --export-debug "$PRESET_NAME" "$IPA_BUILD_PATH"

  [[ -f "$IPA_BUILD_PATH" ]] || { echo "Error: no IPA found at $IPA_BUILD_PATH" >&2; exit 1; }

  echo ""
  echo "Moving IPA to $IPA_FINAL_PATH..."
  mv -f "$IPA_BUILD_PATH" "$IPA_FINAL_PATH"
  [[ -f "$IPA_FINAL_PATH" ]] || { echo "Error: failed to move IPA to $IPA_FINAL_PATH" >&2; exit 1; }
}

# Regenerate altstore.json for the just-built IPA and commit it.
write_altstore_manifest() {
  cd "$ROOT_DIR"
  local size date dl short
  short="${VERSION%+*}"
  size="$(stat -f%z "$IPA_FINAL_PATH")"
  date="$(date +%Y-%m-%d)"
  dl="https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$(basename "$IPA_FINAL_PATH")"

  cat > "$ALTSTORE_MANIFEST" <<JSON
{
  "name": "$APP_NAME",
  "identifier": "$ALTSTORE_SOURCE_ID",
  "sourceURL": "$ALTSTORE_SOURCE_URL",
  "apps": [
    {
      "name": "$APP_NAME",
      "bundleIdentifier": "$BUNDLE_ID",
      "developerName": "ssnanda",
      "subtitle": "Run your HOA. Survive the meeting.",
      "localizedDescription": "Swipe on neighborhood complaints and try to stay HOA president.",
      "iconURL": "$ALTSTORE_ICON_URL",
      "tintColor": "2F4858",
      "screenshotURLs": [],
      "version": "$short",
      "versionDate": "$date",
      "versionDescription": "Build $VERSION",
      "downloadURL": "$dl",
      "size": $size,
      "versions": [
        {
          "version": "$short",
          "date": "$date",
          "localizedDescription": "Build $VERSION",
          "downloadURL": "$dl",
          "size": $size,
          "minOSVersion": "$ALTSTORE_MIN_IOS"
        }
      ]
    }
  ],
  "news": []
}
JSON

  git add "$ALTSTORE_MANIFEST"
  if git diff --cached --quiet; then
    echo "AltStore: manifest unchanged"
  else
    git commit -m "AltStore manifest $VERSION"
    echo "AltStore: manifest updated for $VERSION"
  fi
}

# Publish the IPA to ONE rolling release: re-point "ios-latest" at HEAD,
# delete the previous release, create a fresh one with the IPA attached.
publish_latest_ipa() {
  require_gh
  cd "$ROOT_DIR"

  local sha notes
  sha="$(git rev-parse --short HEAD)"
  notes="$APP_NAME iOS — version $VERSION
Built $(date '+%Y-%m-%d %H:%M %Z') from commit $sha.
This release always holds the latest build; older builds are not kept."

  echo "Moving rolling tag $RELEASE_TAG to $sha..."
  git tag -f "$RELEASE_TAG" >/dev/null
  git push -f origin "$RELEASE_TAG"

  if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "Removing previous $RELEASE_TAG release..."
    gh release delete "$RELEASE_TAG" --repo "$GITHUB_REPO" --yes
  fi

  gh release create "$RELEASE_TAG" "$IPA_FINAL_PATH" \
    --repo "$GITHUB_REPO" \
    --title "$RELEASE_TITLE" \
    --notes "$notes" \
    --latest
  echo "GitHub: published $VERSION to $RELEASE_TAG"
  echo "  https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$(basename "$IPA_FINAL_PATH")"
}

VERSION_OVERRIDE=""
BUMP_PART=""
NO_BUMP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION_OVERRIDE="${2:-}"; shift 2 ;;
    --bump) BUMP_PART="${2:-}"; shift 2 ;;
    --no-bump) NO_BUMP="true"; shift ;;
    --delete) DELETE_ONLY="true"; shift ;;
    --repo) GITHUB_REPO="${2:-}"; shift 2 ;;
    --push) GIT_PUSH="true"; shift ;;
    --publish) GIT_PUSH="true"; GITHUB_RELEASE="true"; shift ;;
    --no-git-commit) GIT_COMMIT="false"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$DELETE_ONLY" == "true" ]]; then delete_old_ipa; exit 0; fi

require_files
require_git

CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"

RUN_BUMP="false"
if [[ -n "$VERSION_OVERRIDE" || -n "$BUMP_PART" || "$NO_BUMP" == "true" ]]; then
  RUN_BUMP="true"
elif working_tree_dirty; then
  echo "Uncommitted changes detected — running 1-bump-version.sh"
  RUN_BUMP="true"
else
  echo "Working tree clean and no --bump/--version — building current version $CURRENT_VERSION"
fi

if [[ "$RUN_BUMP" == "true" ]]; then
  BUMP_ARGS=()
  [[ -n "$VERSION_OVERRIDE" ]] && BUMP_ARGS+=(--version "$VERSION_OVERRIDE")
  [[ -n "$BUMP_PART" ]] && BUMP_ARGS+=(--bump "$BUMP_PART")
  [[ "$NO_BUMP" == "true" ]] && BUMP_ARGS+=(--no-bump)
  [[ "$GIT_COMMIT" == "true" ]] || BUMP_ARGS+=(--no-commit)
  BUMP_ARGS+=(--no-push)  # this script pushes after the build
  "$BIN_DIR/1-bump-version.sh" ${BUMP_ARGS[@]+"${BUMP_ARGS[@]}"}
fi

VERSION="$(get_version)"
validate_version "$VERSION"

if [[ "$GIT_PUSH" == "true" ]]; then
  git_sync_branch
fi

echo ""
echo "════════════════════════════════════════"
echo "  $APP_NAME — IPA Builder"
echo "  Bundle: $BUNDLE_ID"
echo "════════════════════════════════════════"
echo "Version: $VERSION"
echo "════════════════════════════════════════"
echo ""

delete_old_ipa
build_ipa

if [[ "$GITHUB_RELEASE" == "true" && "$GIT_COMMIT" == "true" ]]; then
  write_altstore_manifest
fi

if [[ "$GIT_PUSH" == "true" ]]; then
  git_push_branch
fi

if [[ "$GITHUB_RELEASE" == "true" ]]; then
  publish_latest_ipa
fi

echo ""
echo "════════════════════════════════════════"
echo "  Done!"
echo "════════════════════════════════════════"
echo "Version:    $VERSION"
echo "Built IPA:  $IPA_FINAL_PATH"
if [[ "$GITHUB_RELEASE" == "true" ]]; then
  echo "Release:    https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
  echo "AltStore:   $ALTSTORE_SOURCE_URL"
fi
echo "════════════════════════════════════════"
echo ""
