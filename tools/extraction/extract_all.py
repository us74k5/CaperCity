"""Extract everything usable from the Crime Fighter (1993-2002, Peter Steffen) DOS release.

Usage: python3 -I extract_all.py <game_dir> <out_dir>

Outputs:
  data/*.json      game tables recovered from CRIME.EXE's data segment
  data/levels.json minigame layouts (DATEN/*.LEV)
  data/strings_*.json all Pascal strings from CRIME.EXE / CRIME.OVR (game text, DE+EN)
  images/*.png     every graphic (CUT/SPF), decoded with the default EGA palette
  tiles/*.png      the 127 city tiles in map-value order
  city/*.png       the full city map, rendered
  sounds/*.wav     PC-speaker melodies
"""
import json, os, struct, sys, wave, math, glob, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cfimg
from PIL import Image

GAME, OUT = sys.argv[1], sys.argv[2]
for sub in ('data', 'images', 'tiles', 'city', 'sounds'):
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)

def save(name, obj):
    with open(os.path.join(OUT, 'data', name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)

# ---------------------------------------------------------------- data segment
exe = open(os.path.join(GAME, 'CRIME.EXE'), 'rb').read()
hdr_paras = struct.unpack_from('<H', exe, 8)[0]
DS = exe[hdr_paras * 16 + 0x31810:]          # DS = 0x3181 (mov ax,3181h; mov ds,ax in startup)

def pstr(o, enc='cp437'):
    n = DS[o]; return DS[o + 1:o + 1 + n].decode(enc)

def u16(o): return struct.unpack_from('<H', DS, o)[0]

# Building types (order = map code // 10 - 10)
BUILD_DE = [pstr(0x346a + i * 21) for i in range(18)]
BUILD_EN = [pstr(0x346a + 18 * 21 + i * 21) for i in range(18)]
ACT_DE = [[pstr(0x140 + (b * 4 + a) * 31) for a in range(4)] for b in range(18)]
ACT_EN = [[pstr(0x9f8 + (b * 4 + a) * 31) for a in range(4)] for b in range(18)]
building_types = []
for i in range(18):
    building_types.append({
        'id': i, 'map_code': 100 + i * 10, 'name_de': BUILD_DE[i], 'name_en': BUILD_EN[i],
        'actions_en': [a for a in ACT_EN[i] if a], 'actions_de': [a for a in ACT_DE[i] if a]})

# City map: 45 x 40 cells, cell = 51x39 px. Layer A = tile graphic, layer B = road/entrance code.
W, H = 45, 40
A = list(DS[0x1f52:0x1f52 + W * H])
B = list(struct.unpack_from('<%dH' % (W * H), DS, 0x265a))
TILE_TAB = DS[0x375e:0x375e + 127 * 3]       # (col,row,sheet) 1-based per tile value 1..127
ROAD = {  # connectivity of road codes (verified against neighbours on the map)
    1: 'NE', 2: 'NW', 3: 'ES', 4: 'SW', 5: 'EW', 6: 'NS', 7: 'NESW', 8: 'NEW', 9: 'ESW', 10: 'NES', 11: 'NSW',
    12: 'motorway_h_upper', 13: 'motorway_h_lower', 14: 'motorway_v_left', 15: 'motorway_v_right', 16: 'motorway_cross'}
buildings = {}
for i, b in enumerate(B):
    if b >= 100:
        t, inst = b // 10 - 10, b % 10
        key = b
        e = buildings.setdefault(key, {'code': b, 'type': t, 'type_en': BUILD_EN[t], 'instance': inst, 'cells': []})
        e['cells'].append([i % W, i // W])
for e in buildings.values():
    xs = [c[0] for c in e['cells']]; ys = [c[1] for c in e['cells']]
    # road cells touching the building = possible entrances
    ent = set()
    for x, y in e['cells']:
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and 0 < B[ny * W + nx] < 100:
                ent.add((nx, ny))
    e['bbox'] = [min(xs), min(ys), max(xs), max(ys)]
    e['adjacent_road_cells'] = sorted([list(p) for p in ent])
save('city.json', {
    'width': W, 'height': H, 'cell_px': [51, 39],
    'tiles': [A[r * W:(r + 1) * W] for r in range(H)],
    'roads': [[b if b < 100 else 0 for b in B[r * W:(r + 1) * W]] for r in range(H)],
    'road_codes': ROAD,
    'buildings': sorted(buildings.values(), key=lambda e: e['code']),
    'note': 'tiles[y][x] indexes tiles/tile_NNN.png; roads[y][x] is a road piece code (0 = not walkable).'})
save('building_types.json', building_types)

# Ranks (10 x string[20])
ranks_de = [pstr(0x4094 + i * 25) for i in range(10)]
save('ranks.json', {'de': ranks_de, 'en_note': 'English rank names live in the overlay; see strings_ovr.json'})

# Cars: string[25] + steps(byte) + price(word). Entry 0 = on foot.
cars = []
o = 0x41a8
for i in range(18):
    cars.append({'id': i, 'name': pstr(o), 'steps': DS[o + 26], 'price_raw': u16(o + 27)})
    o += 29
save('cars.json', cars)

# Weapons: string[16] + reach, precision, effect (tier indices) + price(word) + min_int + min_brut
REACH = ['arm length', 'medium', 'good', 'far', 'always reaches']
PREC = ['bad', 'lousy', 'moderate', 'good', 'very precise', 'dead certain']
EFFECT = ['harmless', 'punchy', 'stabbing', 'good', 'deadly', 'riddling', 'shredding']
weapons = []
o = 0x44ae
for i in range(9):
    r, p, e = DS[o + 17], DS[o + 18], DS[o + 19]
    weapons.append({'id': i + 1, 'name_de': pstr(o), 'reach_tier': r, 'reach': REACH[r - 1],
                    'precision_tier': p, 'precision': PREC[p - 1], 'effect_tier': e, 'effect': EFFECT[e - 1],
                    'price': u16(o + 20), 'min_intelligence': DS[o + 22], 'min_brutality': DS[o + 23],
                    'image': 'WAFFE%d.png' % (i + 1) if i + 1 >= 2 else None})
    o += 24
save('weapons.json', weapons)

# Recruitable gangsters (52 x 31 bytes)
gang = []
o = 0x483c
for i in range(52):
    lo = o + 1                                   # length byte of the name (string[20])
    gang.append({'name': pstr(lo), 'energy': DS[lo + 22], 'strength': DS[lo + 23], 'intelligence': DS[lo + 24],
                 'brutality': DS[lo + 25], 'weapon': DS[lo + 26], 'price': u16(lo + 27), 'flag': DS[lo + 30]})
    o += 31
save('gangsters.json', gang)

# Pickpocket loot: string[30] + value(word)
loot = []
o = 0x4586
while DS[o] and len(loot) < 20:
    loot.append({'item_de': pstr(o), 'value': u16(o + 31)}); o += 33
save('loot.json', loot)

# Holiday destinations (string[17]) and month names
hol = []
o = 0x46f2
for i in range(10):
    hol.append(pstr(o)); o += 21
months = []
o = 0x47c4
for i in range(12):
    months.append(pstr(o)); o += 10
save('misc.json', {'holiday_destinations': hol, 'months_de': months,
                   'blackmail_targets_de': ['des Autohandels', 'des Casinos', 'der Bank', 'des Kaufhauses',
                                            'der Villa', 'Bürgermeister', 'Polizeichef'],
                   'ega_palette': cfimg.EGA})

# ---------------------------------------------------------------- strings (all game text)
def all_pstrings(buf, minlen=3):
    out, i = [], 0
    ok = set(range(32, 127)) | set(range(128, 168)) | {0xe1}
    while i < len(buf) - 1:
        n = buf[i]
        if minlen <= n and i + 1 + n <= len(buf):
            s = buf[i + 1:i + 1 + n]
            if all(c in ok for c in s) and sum(chr(c).isalpha() for c in s) >= n * 0.5:
                out.append({'offset': i, 'text': s.decode('cp437')}); i += 1 + n; continue
        i += 1
    return out
save('strings_exe.json', all_pstrings(exe))
save('strings_ovr.json', all_pstrings(open(os.path.join(GAME, 'CRIME.OVR'), 'rb').read()))

# ---------------------------------------------------------------- levels
FAM = {'FLUCHT': 'police_escape', 'CONTI': 'harbour_containers', 'ZUG': 'mail_train',
       'SCHL': 'sneak_past_guards', 'DIEBST': 'store_theft'}
levels = {}
for p in sorted(glob.glob(os.path.join(GAME, 'DATEN', '*.LEV'))):
    n = os.path.basename(p)[:-4]; fam = re.match(r'[A-Z]+', n).group(0)
    v = [int(x) for x in open(p).read().split()]
    levels.setdefault(FAM[fam], []).append({
        'file': n, 'grid_w': 27, 'grid_h': 20, 'grid': [v[r * 27:(r + 1) * 27] for r in range(20)],
        'params': v[540:],
        'params_note': 'first pair = player start (x,y); FLUCHT/SCHL: next four pairs = police/guard starts'})
lab = [int(x) for x in open(os.path.join(GAME, 'DATEN', 'LAB.DAT')).read().split()]
save('levels.json', {'level_counts_lab_dat': lab, 'families': levels})

# ---------------------------------------------------------------- images
for p in sorted(glob.glob(os.path.join(GAME, '*', '*.SPF')) + glob.glob(os.path.join(GAME, '*', '*.CUT'))):
    im = cfimg.decode(p, order=(3, 2, 1, 0))
    im.save(os.path.join(OUT, 'images', os.path.basename(p).rsplit('.', 1)[0] + '.png'))
sheets = [Image.open(os.path.join(OUT, 'images', n + '.png')).convert('RGB') for n in ('STADT', 'STADT2')]
tiles = {}
for v in range(1, 128):
    c, r, s = TILE_TAB[3 * (v - 1):3 * v]
    t = sheets[s - 1].crop(((c - 1) * 51, (r - 1) * 39, c * 51, r * 39)); tiles[v] = t
    t.save(os.path.join(OUT, 'tiles', 'tile_%03d.png' % v))
city = Image.new('RGB', (W * 51, H * 39))
for i, v in enumerate(A):
    city.paste(tiles[v], ((i % W) * 51, (i // W) * 39))
city.save(os.path.join(OUT, 'city', 'city_full.png'))
from PIL import ImageDraw
ov = city.copy(); dr = ImageDraw.Draw(ov)
for e in buildings.values():
    x0, y0, x1, y1 = e['bbox']
    dr.rectangle([x0 * 51, y0 * 39, (x1 + 1) * 51 - 1, (y1 + 1) * 39 - 1], outline=(255, 255, 0), width=3)
    dr.text((x0 * 51 + 3, y0 * 39 + 2), '%s %d' % (e['type_en'], e['instance'] + 1), fill=(255, 255, 255))
ov.save(os.path.join(OUT, 'city', 'city_labeled.png'))

# ---------------------------------------------------------------- sounds (PC speaker: F=Hz, D=ms)
for p in sorted(glob.glob(os.path.join(GAME, 'DATEN', '*.SND'))):
    notes = re.findall(r'F(\d+)\s+D(\d+)', open(p).read())
    rate = 22050; frames = bytearray(); ph = 0.0
    for f, dms in notes:
        f, n = int(f), int(int(dms) * rate / 1000)
        for _ in range(n):
            if f: ph = (ph + f / rate) % 1.0
            frames.append(128 + (40 if (f and ph < 0.5) else (-40 if f else 0)))
    with wave.open(os.path.join(OUT, 'sounds', os.path.basename(p)[:-4] + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(1); w.setframerate(rate); w.writeframes(bytes(frames))
print('done')
