import sys, json, subprocess
f, img, out = sys.argv[1], sys.argv[2], sys.argv[3]
r = subprocess.run(["ffprobe","-v","quiet","-print_format","json","-show_format","-show_streams",f],capture_output=True,text=True)
try: d = json.loads(r.stdout)
except Exception: d = {}
fmt = d.get("format",{}); streams = d.get("streams",[])
audio = [s for s in streams if s.get("codec_type")=="audio"]
tags = {k.lower():v for k,v in (fmt.get("tags") or {}).items()}
res = {"file-type": 1 if audio else 0, "mime-type": "audio/mpeg" if audio else "application/octet-stream"}
if audio:
    res.update({"audio-codec": audio[0].get("codec_name"), "container-format": fmt.get("format_name"),
                "duration_s": float(fmt.get("duration",0))})
    for k in ("title","album","artist"):
        if k in tags: res[k]=tags[k]
json.dump(res, open(out,"w"))
