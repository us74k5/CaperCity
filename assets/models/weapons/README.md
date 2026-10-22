# Weapon models (optional drop-ins)

The game builds every weapon out of simple shapes (scripts/fx/weapon_models.gd), so this folder can stay empty.
To use real models instead, drop a file here named after the weapon:

    club  baton  switchblade  throwing_knife  pistol  rifle  machine_gun  grenade

as `.glb`, `.gltf` or `.fbx` (e.g. `pistol.glb`). It's scaled to the right length and the grip is put in the
fighter's hand automatically. If it comes out turned the wrong way or held at the wrong spot, add
`weapons.json` here:

    {"pistol": {"file": "Pistol_1.fbx", "length": 0.17, "rot": [0, 90, 0], "grip": 0.3}}

- `file`: use a file with a different name
- `length`: how long it is (a fighter is about 0.7 tall)
- `rot`: degrees to turn it so the barrel/blade points forward (+Z)
- `grip`: where the hand holds it, 0 = back end, 1 = front end

Sounds work the same way: put `pistol_1.ogg` (or .wav) etc. in `audio/weapons/` to replace the built-in ones.
