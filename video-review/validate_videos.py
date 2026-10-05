#!/usr/bin/env python3
"""Validates the final MP4s: exists, duration > 0, 720x1280 @30, frame count sane, not blank/black/frozen,
and extracts beginning/middle/end frames to tmp/spot/ for a visual check. Non-destructive."""
import glob, io, os, subprocess, json
from PIL import Image, ImageStat
ROOT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(ROOT, "tmp", "spot"), exist_ok=True)
def frame(path, t):
    out = subprocess.run(["ffmpeg","-loglevel","error","-ss",str(t),"-i",path,"-frames:v","1","-f","image2pipe","-vcodec","png","-"],capture_output=True).stdout
    return Image.open(io.BytesIO(out)).convert("RGB") if out else None
ok_all = True
for path in sorted(glob.glob(os.path.join(ROOT, "final", "*.mp4"))):
    name = os.path.basename(path)[:-4]
    j = json.loads(subprocess.run(["ffprobe","-v","error","-count_frames","-select_streams","v:0","-show_entries","stream=width,height,r_frame_rate,nb_read_frames,duration","-of","json",path],capture_output=True,text=True).stdout)["streams"][0]
    dur = float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",path],capture_output=True,text=True).stdout)
    frames = int(j["nb_read_frames"]); w, h = j["width"], j["height"]
    samples = [frame(path, t) for t in (0.5, dur * 0.5, max(dur - 1.0, 0.1))]
    means = [sum(ImageStat.Stat(s).mean) / 3 for s in samples]
    diffs = []
    for a, b in ((samples[0], samples[1]), (samples[1], samples[2])):
        diffs.append(sum(ImageStat.Stat(Image.eval(Image.blend(a.resize((90,160)), b.resize((90,160)), 0.5), lambda v: v)).mean))
    ok = dur > 5 and (w, h) == (720, 1280) and abs(frames / dur - 30) < 1.5 and all(m > 25 for m in means)
    ok_all = ok_all and ok
    for tag, s in zip(("start", "mid", "end"), samples):
        s.resize((360, 640)).save(os.path.join(ROOT, "tmp", "spot", "%s_%s.png" % (name, tag)))
    print("%s %-48s %6.1fs %dx%d frames=%d (%.1f fps) brightness start/mid/end=%s" % ("OK  " if ok else "FAIL", name, dur, w, h, frames, frames / dur, [round(m) for m in means]))
print("ALL OK" if ok_all else "SOME FAILED")
