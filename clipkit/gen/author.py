"""Skrip penulis klip (alat kerja, di luar repo): pose per waktu -> clips/<nama>.json (format ClipKit)."""
import json, math

L1, L2 = 0.426, 0.402
REST_H = L1 + L2

def leg_h(a, k):  # tinggi pinggul di atas telapak (m)
    return L1*math.cos(math.radians(a)) + L2*math.cos(math.radians(a-k))
def leg_x(a, k):  # posisi telapak di depan pinggul (m)
    return L1*math.sin(math.radians(a)) + L2*math.sin(math.radians(a-k))

DEFAULT = {"armL_elev":-75,"armR_elev":-75,"elbowL":10,"elbowR":10}

def build(name, duration, poses, easing="inOutSine", **meta):
    """poses: [(t, {channel: nilai} | {channel: (nilai, easing)})]; kanal yang tak disebut di sebuah pose dipertahankan."""
    chans = {}
    for t, p in poses:
        for ch, v in p.items():
            e = easing
            if isinstance(v, tuple): v, e = v
            chans.setdefault(ch, []).append([round(t,4), v, e])
    for ch, keys in chans.items():
        keys.sort(key=lambda k:k[0])
        if keys[0][0] > 0:  # pastikan ada key di t=0 (nilai default rig)
            d = DEFAULT.get(ch, 0)
            keys.insert(0, [0, d, easing])
        keys[0] = keys[0][:2]  # key pertama tanpa easing
    clip = {"name":name, "format_version":1, "version":1,
            "changelog":[{"v":1,"catatan":meta.pop("catatan","Versi awal.")}],
            "group":"combat", "tags":meta.pop("tags",["attack","punch","placeholder-pose"]),
            "duration":duration, "loop":meta.pop("loop",False), "channels":chans}
    clip.update(meta)
    return clip

def save(clip, path):
    json.dump(clip, open(path,"w"), indent=1, ensure_ascii=False)
