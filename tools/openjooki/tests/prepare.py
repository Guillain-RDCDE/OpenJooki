"""Decode YOUR Jooki's player.lib into player.lua (original) and player.patched.lua (with lua_patches)."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import lua_patches as L
src = L.decode(open(sys.argv[1], "rb").read())
here = os.path.dirname(os.path.abspath(__file__))
open(os.path.join(here, "player.lua"), "w", encoding="latin-1").write(src)
open(os.path.join(here, "player.patched.lua"), "w", encoding="latin-1").write(L.apply(src))
print("player.lua + player.patched.lua written")
