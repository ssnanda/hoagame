#!/bin/zsh
# Records the gameplay review videos with Godot Movie Maker and converts them to MP4.
#   ./bin/capture-review-videos.sh            # all videos
#   ./bin/capture-review-videos.sh 01 03      # selected videos
# Output: video-review/final/*.mp4 (temporary AVI + logs in video-review/tmp/). Non-destructive:
# nothing is deleted; every run uses a fresh throwaway HOME so the player's real saves are never touched.
# NOTE: Godot only draws a window that is on screen, so the game window appears briefly on the
# Mac display while a clip records (720x1280 at 30 fps). Do not cover it while capturing.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TMP="$ROOT/video-review/tmp"
FINAL="$ROOT/video-review/final"
PROJ="$TMP/capture_project"
mkdir -p "$TMP" "$FINAL" "$PROJ"

# Capture project: symlinks to the real project, minus the small-window override so the movie is 720x1280.
for d in scripts data scenes tools .godot; do ln -sfn "$ROOT/$d" "$PROJ/$d"; done
ln -sf "$ROOT/icon.svg" "$PROJ/icon.svg"; ln -sf "$ROOT/icon.svg.import" "$PROJ/icon.svg.import"; ln -sf "$ROOT/VERSION" "$PROJ/VERSION"
grep -v "window_width_override\|window_height_override" "$ROOT/project.godot" > "$PROJ/project.godot"

typeset -A NAMES
NAMES=(00 00_poc 01 01_new_game_full_core_loop 02 02_find_the_complaint_navigation 03 03_sidewalk_walkability_and_property_access
  04 04_camera_and_ui_escape_stress_test 05 05_reinspection_full_flow 06 06_sidewalk_obstruction_case
  07 07_cinematic_comedy_showcase 08 08_alive_neighborhood_and_weather 09 09_false_complaint_and_borderline_case)

ids=("$@"); [[ ${#ids[@]} -eq 0 ]] && ids=(01 02 03 04 05 06 07 08 09)
for id in $ids; do
  name="${NAMES[$id]}"; [[ -z "$name" ]] && { echo "unknown video $id"; continue; }
  scene="res://tools/video/video_$name.tscn"
  stamp="$(date +%Y%m%d-%H%M%S)"
  avi="$TMP/$name.avi"; log="$TMP/$name.log"; mp4="$FINAL/$name.mp4"
  echo "== $id: recording $name"
  # Watchdog: a hung capture (e.g. a script parse error leaves a blank scene running) is killed after MAXSEC.
  ( cd "$PROJ" && HOME="$TMP/home_${id}_$stamp" "$GODOT" --path . --write-movie "$avi" --fixed-fps 30 --disable-vsync \
      --resolution 720x1280 --position 40,0 --always-on-top "$scene" > "$log" 2>&1 ) &
  gpid=$!
  waited=0
  while kill -0 $gpid 2>/dev/null; do
    sleep 2; waited=$((waited+2))
    if grep -q "Parse Error\|SCRIPT ERROR: Compile" "$log" 2>/dev/null; then echo "   script error, stopping (see $log)"; pkill -P $gpid 2>/dev/null; kill $gpid 2>/dev/null; break; fi
    if [[ $waited -gt ${MAXSEC:-1500} ]]; then echo "   watchdog timeout, stopping"; pkill -P $gpid 2>/dev/null; kill $gpid 2>/dev/null; break; fi
  done
  wait $gpid 2>/dev/null
  [[ -s "$avi" ]] || { echo "   FAILED: no movie written (see $log)"; continue; }
  ffmpeg -y -loglevel error -i "$avi" -c:v libx264 -preset medium -crf 27 -maxrate 2200k -bufsize 4400k -pix_fmt yuv420p -r 30 -c:a aac -b:a 96k -movflags +faststart "$mp4"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4")
  size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$mp4")
  bytes=$(stat -f%z "$mp4")
  warn=$(grep -c "VIDEO:" "$log")
  echo "   $mp4  ${dur}s  $size  ${bytes} bytes  capture-warnings=$warn"
done
