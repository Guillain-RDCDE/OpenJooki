"""Builds tokimg/: the ready-made token pictures of the page (docs/23 §5).

    python tools/openjooki/webui/make_tokimg.py

Fluent Emoji 3D (github.com/microsoft/fluentui-emoji, MIT, tokimg/LICENSE.txt), the pictures
chosen below for children (no weapons, alcohol, tobacco, flags, religious or office symbols),
reduced to 128 px WebP. tokimg/index.json gives each picture its family, its names in French,
English and Dutch (Unicode CLDR; the French ones shortened by hand below) and its search words
(CLDR keywords of the three languages, accents removed, plus children's words). Needs Internet
and Pillow; the downloads are kept in a cache folder next to this script (not in git).
"""
import concurrent.futures as cf
import json
import os
import re
import shutil
import unicodedata
import urllib.parse
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tokimg")
CACHE = os.path.join(HERE, ".tokimg-cache")
FLUENT = "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/"
CLDR = "https://cdn.jsdelivr.net/npm/cldr-annotations%s-full@46/annotations%s/%s/annotations.json"

# family id: (French, English, Dutch, icon), then the Fluent folder names, in the order shown
FAMILIES = [
    ("animals", "Animaux", "Animals", "Dieren", "cat", "Cat|Cat face|Black cat|Dog|Dog face|Poodle|Mouse face|Hamster|Rabbit|Rabbit face|Horse|Horse face|Donkey|Cow|Cow face|Ox|Pig|Pig face|Ewe|Ram|Goat|Llama|Chicken|Rooster|Baby chick|Hatching chick|Front-facing baby chick|Duck|Goose|Turkey|Fox|Wolf|Bear|Polar bear|Panda|Koala|Lion|Tiger|Tiger face|Leopard|Elephant|Mammoth|Giraffe|Zebra|Hippopotamus|Rhinoceros|Camel|Two-hump camel|Kangaroo|Monkey|Monkey face|Gorilla|Orangutan|Sloth|Otter|Skunk|Raccoon|Badger|Beaver|Hedgehog|Chipmunk|Bat|Deer|Moose|Bison|Boar|Water buffalo|Frog|Turtle|Lizard|Snake|Crocodile|Sauropod|T-rex|Paw prints"),
    ("sea", "Mer et rivière", "Sea and river", "Zee en rivier", "tropical_fish", "Spouting whale|Whale|Dolphin|Seal|Shark|Fish|Tropical fish|Blowfish|Octopus|Squid|Jellyfish|Crab|Lobster|Shrimp|Spiral shell|Coral|Water wave"),
    ("birds", "Oiseaux", "Birds", "Vogels", "owl", "Bird|Owl|Eagle|Parrot|Peacock|Flamingo|Swan|Dove|Penguin|Blackbird|Dodo|Feather|Nest with eggs"),
    ("bugs", "Petites bêtes", "Little creatures", "Kleine beestjes", "butterfly", "Butterfly|Lady beetle|Honeybee|Snail|Ant|Beetle|Bug|Cricket|Worm|Spider|Spider web|Fly"),
    ("tales", "Contes et magie", "Tales and magic", "Sprookjes en magie", "unicorn", "Unicorn|Dragon|Dragon face|Phoenix bird|Person fairy|Person mage|Woman mage|Person genie|Woman merpeople|Person elf|Prince|Princess|Person with crown|Crown|Castle|Magic wand|Crystal ball|Ghost|Alien|Alien monster|Flying saucer|Robot|Ninja|Person superhero|Woman superhero|Troll|Ogre|Person vampire|Skull and crossbones|Santa claus|Mrs claus|Baby angel|Shield|Nesting dolls|Gem stone|Old key|Scroll"),
    ("people", "Famille et métiers", "Family and jobs", "Familie en beroepen", "older_person", "Baby|Child|Girl|Boy|Person|Woman|Man|Older person|Old woman|Old man|People hugging|Person feeding baby|Astronaut|Firefighter|Police officer|Health worker|Cook|Farmer|Teacher|Scientist|Pilot|Detective|Construction worker|Mechanic|Artist|Singer|Student|Guard|Person juggling|Person cartwheeling|Person swimming|Person surfing|Person biking|Skier|Snowboarder|Person in bed|Waving hand|Thumbs up|Clapping hands|Heart hands|Ok hand|Victory hand"),
    ("faces", "Visages et émotions", "Faces and feelings", "Gezichten en gevoelens", "grinning_face_with_big_eyes", "Grinning face|Grinning face with big eyes|Grinning face with smiling eyes|Beaming face with smiling eyes|Grinning squinting face|Face with tears of joy|Rolling on the floor laughing|Slightly smiling face|Smiling face with smiling eyes|Smiling face with halo|Smiling face with hearts|Smiling face with heart-eyes|Star-struck|Face blowing a kiss|Winking face|Face with tongue|Zany face|Hugging face|Thinking face|Shushing face|Nerd face|Smiling face with sunglasses|Cowboy hat face|Partying face|Clown face|Face with monocle|Upside-down face|Melting face|Sleepy face|Sleeping face|Yawning face|Astonished face|Fearful face|Face screaming in fear|Crying face|Loudly crying face|Pouting face|Angry face|Pleading face|Cold face|Hot face|Face with spiral eyes|Pile of poo|See-no-evil monkey|Hear-no-evil monkey|Speak-no-evil monkey|Grinning cat|Smiling cat with heart-eyes|Kissing cat|Cat with tears of joy|Weary cat|Crying cat|Pouting cat"),
    ("hearts", "Cœurs, couleurs et chiffres", "Hearts, colours and numbers", "Hartjes, kleuren en cijfers", "red_heart", "Red heart|Orange heart|Yellow heart|Green heart|Light blue heart|Blue heart|Purple heart|Pink heart|Brown heart|White heart|Black heart|Grey heart|Sparkling heart|Two hearts|Revolving hearts|Heart with ribbon|Heart with arrow|Love letter|Sparkles|Star|Glowing star|Dizzy|Hundred points|Red question mark|Red exclamation mark|Check mark button|Red circle|Orange circle|Yellow circle|Green circle|Blue circle|Purple circle|Brown circle|Black circle|White circle|Red square|Orange square|Yellow square|Green square|Blue square|Purple square|Brown square|Keycap 0|Keycap 1|Keycap 2|Keycap 3|Keycap 4|Keycap 5|Keycap 6|Keycap 7|Keycap 8|Keycap 9|Keycap 10|Speech balloon|Thought balloon|Zzz"),
    ("nature", "Nature et météo", "Nature and weather", "Natuur en weer", "sunflower", "Sun|Sun with face|Sun behind cloud|Sun behind rain cloud|Cloud|Cloud with rain|Cloud with snow|Cloud with lightning|Umbrella with rain drops|Rainbow|Tornado|Wind face|Snowflake|Snowman|Fire|Droplet|High voltage|Crescent moon|Full moon|Full moon face|New moon face|First quarter moon face|Shooting star|Night with stars|Sunrise|Sunrise over mountains|Sunset|Rose|Tulip|Sunflower|Cherry blossom|Hibiscus|Blossom|Bouquet|Lotus|Hyacinth|White flower|Deciduous tree|Evergreen tree|Palm tree|Cactus|Four leaf clover|Shamrock|Maple leaf|Fallen leaf|Leaf fluttering in wind|Herb|Seedling|Potted plant|Mushroom|Brown mushroom|Rock|Wood|Volcano|Mountain|Snow-capped mountain|Desert|Desert island|Beach with umbrella|National park"),
    ("space", "Espace", "Space", "Ruimte", "rocket", "Rocket|Ringed planet|Milky way|Comet|Satellite|Telescope|Globe showing europe-africa|Globe showing americas|Globe showing asia-australia"),
    ("vehicles", "Véhicules", "Vehicles", "Voertuigen", "automobile", "Automobile|Oncoming automobile|Taxi|Racing car|Police car|Ambulance|Fire engine|Bus|Oncoming bus|Minibus|Trolleybus|Tractor|Delivery truck|Articulated lorry|Pickup truck|Sport utility vehicle|Motorcycle|Motor scooter|Kick scooter|Bicycle|Skateboard|Roller skate|Locomotive|Train|High-speed train|Bullet train|Railway car|Tram|Metro|Monorail|Mountain railway|Aerial tramway|Helicopter|Airplane|Small airplane|Airplane departure|Parachute|Sailboat|Canoe|Speedboat|Motor boat|Ship|Passenger ship|Ferry|Anchor|Construction|Fuel pump|Vertical traffic light|Stop sign"),
    ("places", "Lieux et voyages", "Places and travel", "Plaatsen en reizen", "castle", "House|House with garden|Houses|Hut|School|Hospital|Post office|Office building|Stadium|Japanese castle|Tent|Camping|Circus tent|Ferris wheel|Roller coaster|Carousel horse|Playground slide|Fountain|Statue of liberty|Tokyo tower|Mount fuji|Cityscape|Bridge at night|World map|Compass|Luggage|Backpack|Ticket|Admission tickets"),
    ("food", "Miam", "Yum", "Lekker", "strawberry", "Red apple|Green apple|Pear|Tangerine|Lemon|Banana|Watermelon|Grapes|Strawberry|Blueberries|Melon|Cherries|Peach|Mango|Pineapple|Coconut|Kiwi fruit|Tomato|Avocado|Eggplant|Potato|Carrot|Ear of corn|Hot pepper|Bell pepper|Cucumber|Broccoli|Onion|Garlic|Pea pod|Chestnut|Peanuts|Bread|Croissant|Baguette bread|Pretzel|Bagel|Pancakes|Waffle|Cheese wedge|Egg|Cooking|Butter|Sandwich|Hamburger|French fries|Pizza|Hot dog|Taco|Burrito|Spaghetti|Steaming bowl|Pot of food|Green salad|Popcorn|Sushi|Rice ball|Dumpling|Poultry leg|Soft ice cream|Ice cream|Shaved ice|Doughnut|Cookie|Birthday cake|Shortcake|Cupcake|Pie|Chocolate bar|Candy|Lollipop|Custard|Honey pot|Baby bottle|Glass of milk|Hot beverage|Teapot|Cup with straw|Bubble tea|Beverage box|Bowl with spoon|Fork and knife with plate"),
    ("music", "Musique", "Music", "Muziek", "guitar", "Musical notes|Musical note|Musical score|Guitar|Violin|Banjo|Musical keyboard|Accordion|Trumpet|Saxophone|Flute|Drum|Long drum|Maracas|Microphone|Studio microphone|Headphone|Radio|Loudspeaker|Bell|Postal horn|Performing arts|Mirror ball"),
    ("games", "Jeux et sports", "Games and sports", "Spelletjes en sport", "teddy_bear", "Balloon|Kite|Puzzle piece|Yo-yo|Game die|Chess pawn|Joystick|Video game|Teddy bear|Soccer ball|Basketball|American football|Rugby football|Tennis|Volleyball|Baseball|Softball|Ping pong|Badminton|Bowling|Ice hockey|Ice skate|Skis|Sled|Flying disc|Goal net|Bullseye|Trophy|Sports medal|1st place medal|Fishing pole|Diving mask|Artist palette|Crayon|Paintbrush|Framed picture|Yarn|Thread|Ribbon|Wrapped gift|Party popper|Confetti ball|Fireworks|Sparkler|Christmas tree|Jack-o-lantern|Joker"),
    ("home", "École et maison", "School and home", "School en thuis", "books", "Books|Open book|Closed book|Green book|Blue book|Orange book|Notebook with decorative cover|Pencil|Memo|Straight ruler|Triangular ruler|Abacus|Graduation cap|Light bulb|Magnifying glass tilted left|Microscope|Test tube|Magnet|Alarm clock|Hourglass not done|Calendar|Camera|Television|Telephone|Mobile phone|Laptop|Envelope|Package|Key|Bed|Couch and lamp|Chair|Bathtub|Toothbrush|Soap|Bubbles|Basket|Umbrella|Glasses|Sunglasses|T-shirt|Running shoe|Billed cap|Top hat|Scarf|Gloves|Socks|Coat|Dress|Candle|Flashlight|Toolbox|Hammer|Wrench|Gear"),
]

# CLDR's French names are often long ("visage très souriant aux yeux rieurs"): the shorter ones
FR = {
    "Cat face": "Tête de chat", "Lion": "Lion", "Spouting whale": "Baleine qui souffle", "Paw prints": "Empreintes",
    "Person fairy": "Fée", "Person mage": "Magicien", "Woman mage": "Magicienne", "Person with crown": "Roi ou reine",
    "Skull and crossbones": "Pirate", "Baby angel": "Ange", "Man": "Homme", "Woman": "Femme", "Person": "Personne",
    "Person feeding baby": "Parent et bébé", "Police officer": "Policier", "Health worker": "Docteur", "Cook": "Cuisinier",
    "Farmer": "Fermier", "Teacher": "Maîtresse ou maître", "Construction worker": "Ouvrier", "Mechanic": "Mécanicien",
    "Singer": "Chanteur", "Student": "Écolier", "Guard": "Garde royal", "Person juggling": "Jongleur",
    "Person cartwheeling": "Acrobate", "Person swimming": "Nageur", "Person surfing": "Surfeur", "Person in bed": "Au lit",
    "Waving hand": "Coucou", "Thumbs up": "Super", "Heart hands": "Cœur avec les mains", "Ok hand": "OK",
    "Victory hand": "Victoire", "People hugging": "Câlin", "Older person": "Papy ou mamie", "Old woman": "Mamie", "Old man": "Papy",
    "Grinning face": "Sourire", "Grinning face with big eyes": "Grand sourire", "Grinning face with smiling eyes": "Rire",
    "Beaming face with smiling eyes": "Rayonnant", "Grinning squinting face": "Mort de rire", "Face with tears of joy": "Pleurer de rire",
    "Rolling on the floor laughing": "Fou rire", "Slightly smiling face": "Petit sourire", "Smiling face with smiling eyes": "Gentil",
    "Smiling face with halo": "Petit ange", "Smiling face with hearts": "Amoureux", "Smiling face with heart-eyes": "Yeux en cœur",
    "Star-struck": "Émerveillé", "Face blowing a kiss": "Bisou", "Winking face": "Clin d’œil", "Face with tongue": "Tirer la langue",
    "Zany face": "Fou-fou", "Hugging face": "Gros câlin", "Thinking face": "Réfléchir", "Shushing face": "Chut", "Nerd face": "Intello",
    "Smiling face with sunglasses": "Trop cool", "Cowboy hat face": "Cowboy", "Partying face": "C’est la fête", "Clown face": "Clown",
    "Face with monocle": "Monocle", "Upside-down face": "À l’envers", "Melting face": "Qui fond", "Sleepy face": "Somnolent",
    "Sleeping face": "Dodo", "Yawning face": "Bâillement", "Astonished face": "Étonné", "Fearful face": "Peur",
    "Face screaming in fear": "Cri de peur", "Crying face": "Triste", "Loudly crying face": "Gros chagrin", "Pouting face": "Fâché tout rouge",
    "Angry face": "En colère", "Pleading face": "S’il te plaît", "Cold face": "Froid", "Hot face": "Chaud",
    "Face with spiral eyes": "Tête qui tourne", "Pile of poo": "Caca", "See-no-evil monkey": "Singe qui ne voit rien",
    "Hear-no-evil monkey": "Singe qui n’entend rien", "Speak-no-evil monkey": "Singe qui ne dit rien",
    "Dizzy": "Étoile tourbillon", "Hundred points": "100 points", "Check mark button": "Coché", "Speech balloon": "Bulle", "Zzz": "Zzz",
    "Sun behind cloud": "Soleil et nuage", "Sun behind rain cloud": "Averse", "Umbrella with rain drops": "Parapluie sous la pluie",
    "Wind face": "Vent", "High voltage": "Éclair", "Deciduous tree": "Arbre", "Evergreen tree": "Sapin",
    "Sunrise over mountains": "Lever de soleil en montagne", "Beach with umbrella": "Plage", "Blossom": "Fleur", "Herb": "Herbe",
    "Globe showing europe-africa": "Terre (Europe)", "Globe showing americas": "Terre (Amériques)", "Globe showing asia-australia": "Terre (Asie)",
    "Oncoming automobile": "Voiture (de face)", "Oncoming bus": "Bus (de face)", "Sport utility vehicle": "4x4", "Articulated lorry": "Camion",
    "Vertical traffic light": "Feu tricolore", "Ship": "Bateau", "High-speed train": "TGV", "Bullet train": "Train rapide",
    "Office building": "Immeuble", "Luggage": "Valise", "Cheese wedge": "Fromage", "Dumpling": "Raviolis", "Soft ice cream": "Glace à l’italienne",
    "Shortcake": "Fraisier", "Beverage box": "Jus de fruit", "Fork and knife with plate": "À table", "Pea pod": "Petits pois",
    "Steaming bowl": "Soupe", "Postal horn": "Cor", "Performing arts": "Théâtre", "Drum": "Tambour", "Balloon": "Ballon",
    "Goal net": "But", "Bullseye": "Cible", "Flying disc": "Frisbee", "Yarn": "Pelote de laine", "Party popper": "Fête",
    "Joker": "Joker", "Crayon": "Crayon de couleur", "Magnifying glass tilted left": "Loupe", "Hourglass not done": "Sablier",
    "Abacus": "Boulier", "Graduation cap": "Diplôme", "Notebook with decorative cover": "Carnet", "Memo": "Bloc-notes",
    "Billed cap": "Casquette", "Top hat": "Chapeau haut-de-forme", "Umbrella": "Parapluie", "Glasses": "Lunettes",
    "Flashlight": "Lampe de poche", "Gear": "Engrenage", "Alien monster": "Monstre de l’espace", "Person superhero": "Super-héros",
    "Woman superhero": "Super-héroïne", "Basketball": "Ballon de basket", "Soccer ball": "Ballon de foot",
}
# children's words that CLDR does not have
WORDS = {
    "cat": "minou chaton", "cat_face": "minou chaton", "black_cat": "minou", "dog": "toutou chiot", "dog_face": "toutou chiot",
    "rabbit": "lapinou", "horse": "dada poney", "teddy_bear": "doudou nounours", "sleeping_face": "dormir sieste",
    "bed": "dodo dormir sieste", "crescent_moon": "dodo nuit", "automobile": "auto", "old_woman": "grand-mere mamie granny oma",
    "old_man": "grand-pere papy grandpa opa", "older_person": "grand-parent grandparent", "pile_of_poo": "caca",
    "musical_notes": "chanson comptine song", "books": "histoire conte story verhaal", "open_book": "histoire conte story verhaal",
    "baby_bottle": "bebe", "sauropod": "dinosaure dinosaur", "t_rex": "dinosaure dinosaur",
}


def fetch(url, cache_name):
    path = os.path.join(CACHE, cache_name)
    if not os.path.exists(path):
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        open(path, "wb").write(data)
    return open(path, "rb").read()


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def plain(s):
    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")


def cldr(lang):
    a = json.loads(fetch(CLDR % ("", "", lang), "cldr-%s.json" % lang))["annotations"]["annotations"]
    b = json.loads(fetch(CLDR % ("-derived", "Derived", lang), "cldr-derived-%s.json" % lang))["annotationsDerived"]["annotations"]
    return dict(a, **b)


def main():
    os.makedirs(CACHE, exist_ok=True)
    tree = json.loads(fetch("https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/main?recursive=1", "tree.json"))["tree"]
    pic = {}   # folder (lower case) -> (folder, path of its 3D picture; the default skin tone for people)
    for x in tree:
        p = x["path"]
        if p.endswith("_3d.png") or p.endswith("_3d_default.png"):
            pic.setdefault(p.split("/")[1].lower(), (p.split("/")[1], p))
    names = {lang: cldr(lang) for lang in ("fr", "en", "nl")}
    rows = []
    for fam, _fr, _en, _nl, _icon, folders in FAMILIES:
        for f in folders.split("|"):
            folder, path = pic[f.lower()]
            rows.append({"family": fam, "folder": folder, "path": path, "id": slug(folder)})

    def one(r):
        meta = json.loads(fetch(FLUENT + "assets/" + urllib.parse.quote(r["folder"]) + "/metadata.json", "meta-%s.json" % r["id"]))
        code = meta.get("unicode") or (meta.get("unicodeSkintones") or [""])[0]
        chars = "".join(chr(int(c, 16)) for c in code.split())
        words = set(WORDS.get(r["id"], "").split())
        for lang in ("fr", "en", "nl"):
            e = names[lang].get(chars) or names[lang].get(chars.replace("️", "")) or {}
            name = r["folder"].split(" ")[1] if r["folder"].startswith("Keycap ") else (e.get("tts") or [r["folder"]])[0]
            r[lang] = name[:1].upper() + name[1:]
            words.update(plain(w) for w in e.get("default", []))
            words.add(plain(r[lang]))
        if r["folder"] in FR:
            r["fr"] = FR[r["folder"]]
            words.add(plain(r["fr"]))
        r["words"] = " ".join(sorted(w for w in words if w))
        png = fetch(FLUENT + "/".join(urllib.parse.quote(x) for x in r["path"].split("/")), "png-%s.png" % r["id"])
        src = os.path.join(CACHE, "png-%s.png" % r["id"])
        Image.open(src).convert("RGBA").resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, r["id"] + ".webp"), quality=82, method=6)
        return r

    keep = os.path.join(CACHE, "LICENSE.txt")
    shutil.copyfile(os.path.join(OUT, "LICENSE.txt"), keep)
    shutil.rmtree(OUT)
    os.makedirs(OUT)
    shutil.copyfile(keep, os.path.join(OUT, "LICENSE.txt"))
    with cf.ThreadPoolExecutor(16) as ex:
        rows = list(ex.map(one, rows))
    index = {"v": 1, "source": "Fluent Emoji 3D, Microsoft (MIT)",
             "cats": [[fam, {"fr": fr, "en": en, "nl": nl}, icon] for fam, fr, en, nl, icon, _ in FAMILIES],
             "img": [[r["id"], r["family"], r["fr"], r["en"], r["nl"], r["words"]] for r in rows]}
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as fh:
        json.dump(index, fh, ensure_ascii=False, separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(OUT, r["id"] + ".webp")) for r in rows)
    print("%d pictures, %.1f MB, index %d B" % (len(rows), size / 1e6, os.path.getsize(os.path.join(OUT, "index.json"))))


if __name__ == "__main__":
    main()
