"""Fake audio engine for the bench: answers /j/audio/out/* like the Jooki's GStreamer player."""
import json, time, threading, paho.mqtt.client as mqtt
st = {"id": None, "playing": False, "pos": 0, "t": time.time()}
c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "fakeaudio")
def pub(ev, **kw): c.publish("/j/audio/input/" + ev, json.dumps(dict(kw, id=st["id"])))
def on_msg(cl, u, m):
    p = m.payload.decode(); cmd = m.topic.rsplit("/", 1)[1]
    parts = p.split("\t")
    if cmd == "play":
        st.update(id=int(parts[0]), playing=True, pos=0, t=time.time()); pub("starting"); time.sleep(0.1); pub("playing")
    elif cmd == "pauz" and st["id"] is not None: st["playing"] = False; pub("paused")
    elif cmd == "cont" and st["id"] is not None: st.update(playing=True, t=time.time()); pub("playing")
    elif cmd == "stop" and st["id"] is not None: st["playing"] = False; pub("stopped")
    elif cmd == "seek": st.update(pos=int(parts[1]), t=time.time()); pub("position", pos=st["pos"])
c.on_message = on_msg
c.on_connect = lambda cl, u, f, rc, pr=None: cl.subscribe("/j/audio/out/#")
c.connect("127.0.0.1", 1883); c.loop_start()
while True:
    time.sleep(1)
    if st["playing"]:
        st["pos"] += 1000; pub("position", pos=st["pos"])
