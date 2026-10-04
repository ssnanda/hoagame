#!/usr/bin/env bash
set -euo pipefail

# HOA President — version bump + release commit
# ---------------------------------------------
# Resolves the next version, writes it to VERSION (X.Y.Z+B), project.godot and
# export_presets.cfg (short version X.Y.Z, build B), and commits the working tree as
# "Release HOA President X.Y.Z".
#
# Run it directly, or let bin/2a-hoagame-ipa.sh call it — it does so whenever the
# working tree has uncommitted changes (or on --bump / --version / --no-bump).
#
#   ./bin/1-bump-version.sh                 # interactive menu
#   ./bin/1-bump-version.sh --bump patch
#   ./bin/1-bump-version.sh --version 1.2.0+7
#   ./bin/1-bump-version.sh --no-bump       # commit the current version as-is
#   ./bin/1-bump-version.sh --no-push     # commit only
#   ./bin/1-bump-version.sh --no-commit     # only rewrite version files

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
PROJECT_FILE="$ROOT_DIR/project.godot"
PRESET_FILE="$ROOT_DIR/export_presets.cfg"
APP_NAME="HOA President"

DO_COMMIT="true"
DO_PUSH="true"
VERSION_OVERRIDE=""
BUMP_PART=""
NO_BUMP="false"

usage() {
  cat <<'USAGE'
HOA President — version bump + release commit.

Usage:
  ./bin/1-bump-version.sh [options]

Options:
  --version X.Y.Z+B Set an explicit version
  --bump patch|minor|major|build
  --no-bump         Keep the current version (still commits the tree)
  --no-commit       Rewrite version files only; do not commit
  --no-push         Commit only; do not push
  --help

With no --version / --bump / --no-bump, an interactive menu is shown.
The commit skips build artifacts (*.ipa, *.zip, build/, releases/).
USAGE
}

get_version() {
  [[ -f "$VERSION_FILE" ]] || echo "0.1.0+1" > "$VERSION_FILE"
  tr -d '[:space:]' < "$VERSION_FILE"
}

validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || {
    echo "Error: version must use X.Y.Z+B format, example 1.0.0+1" >&2
    exit 1
  }
}

bump_version() {
  local current="$1" part="$2" major minor patch build
  build="${current#*+}"
  IFS='.' read -r major minor patch <<< "${current%+*}"
  case "$part" in
    patch) patch=$((patch + 1)); build=$((build + 1)) ;;
    minor) minor=$((minor + 1)); patch=0; build=$((build + 1)) ;;
    major) major=$((major + 1)); minor=0; patch=0; build=$((build + 1)) ;;
    build) build=$((build + 1)) ;;
    *) echo "Error: bump must be patch, minor, major, or build" >&2; exit 1 ;;
  esac
  echo "$major.$minor.$patch+$build"
}

set_version() {
  local v="$1" short build
  validate_version "$v"
  short="${v%+*}"; build="${v#*+}"
  echo "$v" > "$VERSION_FILE"
  if grep -q '^config/version=' "$PROJECT_FILE"; then
    perl -pi -e "s/^config\/version=.*/config\/version=\"$short\"/" "$PROJECT_FILE"
  else
    perl -pi -e "s/^(config\/name=.*)\$/\$1
config\/version=\"$short\"/" "$PROJECT_FILE"
  fi
  if [[ -f "$PRESET_FILE" ]]; then
    perl -pi -e "s/^application\/short_version=.*/application\/short_version=\"$short\"/; s/^application\/version=.*/application\/version=\"$build\"/" "$PRESET_FILE"
  fi
}

choose_version_from_menu() {
  local current="$1" choice="" custom_version=""

  while true; do
    cat >&2 <<MENU
Current version: $current

Choose release type:
  1) patch  ($(bump_version "$current" patch))
  2) minor  ($(bump_version "$current" minor))
  3) major  ($(bump_version "$current" major))
  4) build  ($(bump_version "$current" build))
  5) custom version
  6) no bump / package current version
MENU

    read -r -p "Enter choice (1-6, default=1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1|patch|p) bump_version "$current" patch; return 0 ;;
      2|minor|m) bump_version "$current" minor; return 0 ;;
      3|major|M) bump_version "$current" major; return 0 ;;
      4|build|b) bump_version "$current" build; return 0 ;;
      5|custom|c)
        read -r -p "Enter version X.Y.Z+B: " custom_version
        validate_version "$custom_version"
        echo "$custom_version"
        return 0
        ;;
      6|none|no|n|current) echo "$current"; return 0 ;;
      *) echo "Please choose 1, 2, 3, 4, 5, or 6." >&2; echo "" >&2 ;;
    esac
  done
}

require_git() {
  command -v git >/dev/null 2>&1 || { echo "Error: git command is required" >&2; exit 1; }
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: $ROOT_DIR is not a git repository" >&2
    exit 1
  }
}

commit_release() {
  require_git
  cd "$ROOT_DIR"

  git add -u

  while IFS= read -r file; do
    case "$file" in
      build/*|releases/*|*.ipa|*.zip) continue ;;
      *) git add "$file" ;;
    esac
  done < <(git ls-files --others --exclude-standard)

  if git diff --cached --quiet; then
    echo "Git: nothing to commit"
    return 0
  fi

  git commit -m "Release $APP_NAME $VERSION"
  echo "Git: committed release $VERSION"
}

push_release() {
  require_git
  cd "$ROOT_DIR"

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"

  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "Git: syncing $branch with origin (pull --rebase)..."
    git pull --rebase origin "$branch" || \
      echo "Warning: 'git pull --rebase origin $branch' failed — pushing local state." >&2
  fi

  git push -u origin "$branch"
  echo "Git: pushed $branch"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION_OVERRIDE="${2:-}"; shift 2 ;;
    --bump) BUMP_PART="${2:-}"; shift 2 ;;
    --no-bump) NO_BUMP="true"; shift ;;
    --no-commit) DO_COMMIT="false"; shift ;;
    --no-push) DO_PUSH="false"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$PROJECT_FILE" ]] || { echo "Error: missing project.godot at $PROJECT_FILE" >&2; exit 1; }

ACTION_COUNT=0
[[ -n "$VERSION_OVERRIDE" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
[[ -n "$BUMP_PART" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
[[ "$NO_BUMP" == "true" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
if (( ACTION_COUNT > 1 )); then
  echo "Error: use only one of --version, --bump, or --no-bump" >&2
  exit 1
fi

CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"

if [[ -n "$VERSION_OVERRIDE" ]]; then
  NEXT_VERSION="$VERSION_OVERRIDE"
elif [[ -n "$BUMP_PART" ]]; then
  NEXT_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_PART")"
elif [[ "$NO_BUMP" == "true" ]]; then
  NEXT_VERSION="$CURRENT_VERSION"
else
  NEXT_VERSION="$(choose_version_from_menu "$CURRENT_VERSION")"
fi

validate_version "$NEXT_VERSION"

set_version "$NEXT_VERSION"
if [[ "$NEXT_VERSION" != "$CURRENT_VERSION" ]]; then
  echo "Version: $CURRENT_VERSION -> $NEXT_VERSION"
else
  echo "Version: $CURRENT_VERSION (unchanged)"
fi

VERSION="$NEXT_VERSION"

if [[ "$DO_COMMIT" == "true" ]]; then
  commit_release
  [[ "$DO_PUSH" == "true" ]] && push_release
fi
