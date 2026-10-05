#!/usr/bin/env python3
"""Builds VIDEO_INDEX.txt from the final MP4s (ffprobe) and the MARK lines the capture driver wrote into
tmp/<name>.log (movie time in seconds). Descriptions/known issues come from notes.json. Non-destructive."""
import json, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.abspath(__file__))
FINAL = os.path.join(ROOT, "final"); TMP = os.path.join(ROOT, "tmp")
notes = json.load(open(os.path.join(ROOT, "notes.json")))

def probe(path):
    out = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration:stream=codec_type,codec_name,width,height,r_frame_rate","-of","json",path],capture_output=True,text=True).stdout
    j = json.loads(out); v = [s for s in j["streams"] if s["codec_type"]=="video"][0]
    has_audio = any(s["codec_type"]=="audio" for s in j["streams"])
    num,den = v["r_frame_rate"].split("/")
    return float(j["format"]["duration"]), v["width"], v["height"], round(int(num)/int(den)), v["codec_name"], has_audio

def mmss(t): return "%02d:%02d" % (int(t)//60, int(t)%60)

def timeline(name):
    log = os.path.join(TMP, name + ".log")
    if not os.path.exists(log): return []
    marks = []
    for line in open(log, errors="ignore"):
        m = re.match(r"MARK\|([\d.]+)\|(.*)", line.strip())
        if m: marks.append((float(m.group(1)), m.group(2)))
    keep, last = [], None
    for t, txt in marks:
        if txt.startswith("state WORLD") and t < 1.5: continue
        if txt.startswith("state MODAL") and t < 1.5: continue
        if txt == last: continue
        last = txt
        if txt.startswith(("state ", "press ", "walk ", "unstick", "answer", "objective")):
            keep.append((t, txt))
    return keep

lines = ["HOA GAME - REVIEW VIDEO INDEX", "=" * 30, "",
         "All clips: 720x1280 portrait, 30 fps, H.264 (yuv420p) + AAC audio, recorded with Godot Movie Maker from the real game.",
         "A small white dot/ring shows where the automated 'finger' touches. Titles at the start are 1.4 s cards.",
         "Regenerate any clip:  ./bin/capture-review-videos.sh NN   (then: python3 video-review/make_index.py)", ""]
for name in sorted(notes):
    path = os.path.join(FINAL, name + ".mp4")
    if not os.path.exists(path):
        lines += [name + ".mp4  -- NOT PRODUCED", ""]; continue
    dur, w, h, fps, codec, audio = probe(path)
    n = notes[name]
    lines += ["-" * 78, name + ".mp4", "-" * 78,
              "duration: %s (%.1f s)   size: %dx%d   fps: %d   codec: %s   audio: %s   file: %.1f MB" % (mmss(dur), dur, w, h, fps, codec, "yes" if audio else "no", os.path.getsize(path)/1e6),
              "seed: " + n["seed"], "command: ./bin/capture-review-videos.sh " + n["id"],
              "setup: " + n["setup"], "proves: " + n["proves"],
              "movement: " + n["movement"], "input: " + n["input"],
              "known issues visible in the clip: " + n["issues"], "", "timestamps (auto-logged by the driver; movie time):"]
    for t, txt in timeline(name):
        lines.append("  %s  %s" % (mmss(t), txt))
    lines.append("")
open(os.path.join(ROOT, "VIDEO_INDEX.txt"), "w").write("\n".join(lines))
print("wrote VIDEO_INDEX.txt")
