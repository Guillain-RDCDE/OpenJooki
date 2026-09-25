"""Seed the bench with a demo library (public-domain works, fake token ids, fake audio)."""
import json, shutil, hashlib, os
HERE = os.path.dirname(os.path.abspath(__file__))
DB = "/jooki/external/jooki"
ALBUMS = {
    "Comptines": ["Alouette", "Au clair de la lune", "Frère Jacques", "Une souris verte", "Il était un petit navire"],
    "Comptines 2": ["Un grand cerf", "Petit escargot", "Jean de la Lune"],
    "Comptines 3": ["Pomme de reinette", "Il pleut il mouille", "Dame Tartine", "Polichinelle"],
    "Le carnaval des animaux": ["Introduction et Marche royale du Lion", "Poules et coqs", "Hémiones", "Tortues", "L'Eléphant", "Le Cygne", "Finale"],
    "Pierre et le Loup": ["Introduction", "Pierre se promène", "Le canard", "Le chat", "Le grand-père", "Le loup", "Les chasseurs"],
    "Chansons de marins": ["La mer est sans fin", "Tri Martolod", "Les Prisons de Nantes"],
}
tracks = {"_": {"version": 1}}
by = {}
for album, titles in ALBUMS.items():
    for i, title in enumerate(titles):
        tid = hashlib.md5((album + title).encode()).hexdigest()[:16]
        shutil.copy(os.path.join(HERE, "media/song1.mp3"), "%s/uploads/%s" % (DB, tid))
        tracks[tid] = {"title": title, "album": album, "artist": "Démo", "duration": 120 + i * 7,
                       "filename": "%s/uploads/%s" % (DB, tid), "userFilename": "%02d - %s.mp3" % (i + 1, title), "size": 24556}
        by.setdefault(album, []).append(tid)
tid = hashlib.md5(b"tone").hexdigest()[:16]
shutil.copy(os.path.join(HERE, "media/song2.mp3"), "%s/uploads/%s" % (DB, tid))
tracks[tid] = {"title": "Test Tone", "album": "Tests", "artist": "OpenJooki", "duration": 3, "filename": "%s/uploads/%s" % (DB, tid), "userFilename": "test-tone.mp3"}
json.dump(tracks, open(DB + "/tracks.json", "w"))
T = {  # fake token ids (14 hex chars)
    "04000000D00001": ("Jooki.Dragon", "Dragon"), "04000000D00002": ("Jooki.Dragon", None),
    "04000000F00001": ("Jooki.Fox", None), "04000000F00002": ("Jooki.Fox", "Renard"),
    "04000000B00001": ("Jooki.Black.Dragon", "Dark Dragon"), "04000000B00002": ("Jooki.Black.Whale", "Dark Baleine"),
    "04000000G00001": ("Jooki.Ghost", None), "04000000K00001": ("Jooki.Knight", "Chevalier"),
    "04000000W00001": ("Jooki.Whale", "Baleine"), "04000000A00001": ("G2.DarkBlue", "Jeton bleu"),
}
tokens = {"_": {"version": 1}}
for tag, (star, name) in T.items():
    tokens[tag] = {"starId": star, "seen": 3}
    if name: tokens[tag]["name"] = name
json.dump(tokens, open(DB + "/tokens.json", "w"))
pl = {"_": {"version": 1},
      "user_1": {"title": "Comptines 1", "tagId": "04000000B00001", "tracks": by["Comptines"]},   # old per-token link (migrated at boot)
      "user_2": {"title": "Comptines 2", "star": "Jooki.Fox", "tracks": by["Comptines 2"]},
      "user_3": {"title": "Comptines 3", "star": "Jooki.Ghost", "tracks": by["Comptines 3"]},
      "user_4": {"title": "Le carnaval des animaux", "star": "Jooki.Whale", "tracks": by["Le carnaval des animaux"]},
      "user_5": {"title": "Pierre et le Loup", "star": "Jooki.Dragon", "tracks": by["Pierre et le Loup"]},
      "user_6": {"title": "Chansons de marins", "star": "Jooki.Knight", "tracks": by["Chansons de marins"]}}
json.dump(pl, open(DB + "/playlists.json", "w"))
print(len(tracks) - 1, "tracks seeded")
