Low Poly RPG Items Free
=======================

16 low-poly RPG items for a hero's first kit, taken from Low Poly RPG Items (142 props: weapons,
shields, armour, magic, potions, books, keys, treasure, food and tools, and an armoury to walk):
https://heyheythere.itch.io/low-poly-rpg-items
One 2048x2048 texture atlas filtered with mipmaps, the occlusion baked into vertex colours,
real-world scale (1 unit = 1 metre).

What's in the zip
-----------------
glb/        one file per prop, with its animations (the best format for Godot, Blender, three.js)
fbx/        one file per prop, with its animations as takes (Unreal, Unity, most 3D apps)
obj/        one file per prop, still (any 3D app)
textures/   atlas.png, the one texture every prop uses, and its glow map
icons/      an icon per prop, 256x256 PNG with transparency, for an inventory
props.json  every prop: title, group, size, triangles, parts, animations, its "pickup" (what
            taking it gives, and the title and text an inventory shows) and a held prop's "melee"
            (its swing, when the blow lands, its reach)
blender/    every prop in one .blend, the atlas packed in
addons/     the Godot addon, low_poly_rpg_items/: this folder is a Godot 4.3 to 4.7 project that
            opens on its gallery (.gdignore keeps Godot out of the other folders)

Pivots
------
A held item (the sword, the axe, the bow, the staff) has its pivot in its grip, upright, its edge
or arrow towards -Y in Blender (+Z in Godot): parent it to a hand. An item that lies or stands has
its pivot on the ground under it. The shield hangs on a wall, its pivot on the wall's face at the
floor, its middle 1.4 m up. The floor covers a 2 x 2 m cell; the wall is 2 m long and 0.25 m
thick, centred on a cell's edge; the table's top is at 0.8 m.

Godot 4.3 to 4.7
----------------
Copy addons/low_poly_rpg_items/ into your project's addons/ folder. Each prop is a scene in props/
with a box collider (StaticBody3D) on each of its parts, and an AnimationPlayer where it moves:
"swing" on the sword, the axe and the staff, "shoot" on the bow (the arrow flies), "open" on the
chest. An item you can take has pickup.gd on its scene root: use() puts it in what the player
carries and removes it, and the chest opens and shuts:

    key_iron.picked.connect(func(item): print("got ", item))   # in your level
    key_iron.use(carried)                     # carried: the player's items, an Array of names

demo/gallery.tscn shows every prop (drag to turn, arrows to browse, A for all of them, I to hold
an item up and read it) and the range (G: each weapon in hand, left button to swing it).
Low Poly RPG Items uses the same addon folder: it installs over this one.
The props use one material, props.tres: the atlas times the vertex colours, lit, with the glow map.

Other engines and apps
----------------------
Use fbx/, glb/ or obj/ with textures/atlas.png, filtered, with mipmaps, multiplied by the vertex
colours (the baked occlusion) in your material. The scripts are Godot's; elsewhere the animations
are there to play, and props.json says what each item is and what taking it gives.

License: CC BY 4.0, see LICENSE.txt for the credit line. Made by heyheythere:
https://heyheythere.itch.io
