# Caper City: Design Document

Status: draft 2 (19 Oct 2026). **Caper City** is an original game *inspired by* the DOS game *Crime Fighter* (1993–2002).
It is not a port or remake. Sections 1–9 describe the original as reference material, and §0 says how Caper City departs from it.
Facts marked **[orig]** were recovered from the original game files. Facts marked **[new]** are Caper City decisions. **[TBD]** items are still open.

---

## 0. Caper City vs. the original

### 0.1 Clean-room rule
We keep the original's **game structure**: a step budget per turn, entering buildings to pick actions, hiring and training a crew, gear requirements, police checks with escape or bribe, turn-based grid fights, real-time minigames, monthly rounds, and a race to the top rank. Game mechanics and genre conventions are not protected by copyright.

We **do not copy** any of the original's expression into Caper City:
- **No original art, sound or text.** Not as final assets, and not as placeholders that ship.
- **No original names** for characters, businesses or items.
- **No copied city layout or minigame levels.** We design new ones. The extracted map stays a reference for *scale and density* only (about 64 buildings, 18 types, a motorway ring).
- **Numbers are retuned.** The original tables (`extraction/output/data`) are a starting reference for balance ranges, and every value is re-derived in our own balance sheet.

The `extraction/` folder is kept for reference and stays out of the shipped game.

### 0.2 Tone
Dark crime comedy for adults, like the original: armed gang wars, hits, robberies and kidnapping, played with a wink. Target rating: **17+ / Mature**.

All of the original's crimes stay in as mechanics. That includes gun fights where people die, contract hits, and kidnapping children for ransom or selling them to the bartender. What changes is names, art and text, so that everything is our own.

### 0.3 Changes from the original
| Original | Caper City |
|---|---|
| Contract killing (pub assignment) | Kept: **Hit job** |
| Kidnap children (playground, villa) → ransom or sell to the bartender | Kept, with the same mechanics: kidnap, ransom drop, chase minigame, or sell. Presentation rules in §0.5 |
| Kidnap a state visitor | Kept: **Snatch the visiting dignitary** |
| Weapons: hands, club, baton, knife, throwing stars, pistol, rifle, machine gun, grenades | Kept as real weapon types, with generic names and no brands |
| Energy / Strength / Intelligence / Brutality | **Stamina / Muscle / Smarts / Nerve** (same roles) |
| Ranks | Rookie · Small Fry · Hustler · Operator · Crew Boss · Big Shot · Kingpin · Public Enemy · Mastermind · **Boss of Caper City** |
| Real car brands | Fictional makes (e.g. "Puntino", "Brisa GT", "Vortex 900") |
| Duds Dave (counterfeiter) | **The Print Shop**: fake cash, fake IDs |
| Loan shark | **Easy Eddie's Loans** |
| Pub assignments, protection money, blackmail | Kept as-is |
| DM currency | $ |

### 0.5 Content and store risk (decision: keep everything)
The owner has decided to keep all of the original's content. The child-kidnapping mechanics carry the highest risk of rejection from the Apple and Google stores, and mainstream games avoid this content. To give the game its best chance while keeping the mechanic, the presentation follows the original:
- **Kidnappings happen in text** (menu and result screens), the same way the original handled them.
- **Children are never shown being hurt.** They can't appear in fights or be shot, and the chase minigame shows the kid running off with the ransom case (as in the original).
- **Child sprites only appear as small, neutral figures** on the playground and villa tiles.
- **A "Classic content" toggle**, on by default. If a store requires changes, a build-time flag can swap the child targets for adult ones without touching the rest of the game.
- **Release order:** ship on PC (Steam/itch.io) and the web first, where this content is less likely to be a problem. Submit to the mobile stores with a 17+/Mature rating and accurate content descriptors, and use the toggle above only if a store rejects the game.

### 0.4 Visual direction
Top-down 2D in the spirit of 90s overhead crime games: flat roofs with parapets, AC units and roof signs, chunky cars, readable streets. The palette is dusk asphalt with three accents: coral (you and calls to action), teal (spectating, routes, info) and sign-yellow (money). Type: Bungee for signage and headings, Barlow for UI. The canvas "Caper City – Look & Feel" shows the title screen, your turn, a friend's spectator view, a building menu and the crew screen.

---

## 1. The game in one paragraph

Two to four gangsters, just released from prison, compete to become *Boss of the Underworld*. Each month (round), every player takes one turn. In that turn they move through a top-down city with a limited number of steps and enter buildings to commit crimes. They can also buy cars and weapons, hire and train gang members, and pay off the police. Each successful crime earns 1 point. Points raise your rank, and rank unlocks bigger crimes but also attracts tougher police. The first player to reach the target score wins.

## 2. What the original is made of [orig]

| Piece | Format | Status |
|---|---|---|
| Executable | Turbo Pascal 7, real mode, Borland overlays (`CRIME.OVR`, "FBOV") | Data segment fully mapped; game logic lives in overlay code (needs disassembly for formulas) |
| City map | 45 × 40 cells, two layers inside the EXE data segment (DS:1F52 tiles, DS:265A roads/entrances) | **Fully decoded and rendered** |
| City tiles | `STADT.SPF`, `STADT2.SPF`: 640×350 EGA sheets, 51×39 tiles, lookup table at DS:375E | **Decoded**: 127 tiles |
| Graphics | `.CUT`/`.SPF` = size-prefixed Borland `GetImage` blocks (4 bit planes, reversed order); some `.SPF` are IFF ILBM | **All 84 images decoded** |
| Minigame levels | `*.LEV`: 27×20 grid as text + 14 parameters | **45 levels decoded** (8 escape, 10 container, 9 train, 9 sneak, 9 theft) |
| Sounds | `*.SND`: PC-speaker note lists (`F<Hz> D<ms>`) | Converted to WAV |
| Text | Pascal strings in EXE + OVR, German and English side by side | ~3,800 strings extracted |
| Tables | Cars, weapons, gangsters, ranks, loot, holidays, building actions | **Extracted to JSON** |

All extracted data is in `extraction/output/data/*.json`. The tools that produced it are in `extraction/tools/` and can be re-run.

## 3. Core loop

### 3.1 Game setup [orig → new]
- Choose the target score (original suggestion: 50 for a full game, 20 for a short one). **[new]** Presets: Quick (20), Standard (35), Long (50).
- Each player enters a name and a gang name.
- Character stats are rolled 1–99 with a "stop the spinning number" interaction: **Strength** (energy regeneration), **Intelligence** (crime success, weapon requirements), **Brutality** (weapon requirements, intimidation). Starting cash is random.
  - **[new]** Keep the stop-the-slot moment. It's fun to watch as a spectator. Add a 3-reroll limit so nobody stalls the lobby.

### 3.2 A round = a month
1. Start-of-turn events for the active player: rent due, loan collectors, prison sentence, rank-up message, protection money income, credit-store profits.
2. Main menu: **Overview**, **Run through town** (once per round), **Gang war**, **Next player**, **Options**.
3. Run through town: move with a step budget and enter buildings (§4–5).
4. When every player has moved, the month ends and a standings screen shows the ranking.

Players in prison, on holiday, or doing legal work skip turns for N months.

### 3.3 Winning [orig]
- First player whose points reach the target becomes *Boss of the Underworld*.
- Tie-break: if several players cross the line in the same month, they compete in a **container-stealing duel** (harbour minigame). The most containers stolen wins.
- Ranks scale with the target score (changing the target re-rates everyone). 11 titles:
  Beginner → Little fish → Pickpocket → Swindler → Crook → Gang-leader → Felon → Big fish → *Terrorist* → *Public enemy no. 1* → Boss of the underworld.
  **[new]** Rename "Terrorist" (store-review risk), for example to "Kingpin".
- Rank gates: you can hire gangsters only from **Crook** upward. Protection money needs status. Lawyers become available at higher ranks. **[TBD]** Exact rank thresholds as a fraction of the target score.

## 4. The city [orig]

- 45 × 40 cells, each cell 51×39 px in the original. Rendered in full in `extraction/output/city/city_full.png` (labeled version: `city_labeled.png`).
- **Road layer codes:** 1–4 corners, 5/6 straight, 7 crossroads, 8–11 T-junctions, 12/13 horizontal motorway lanes, 14/15 vertical motorway lanes, 16 motorway intersection. Connectivity is in `city.json → road_codes`.
- **Motorway:** cars only. Each lane is one-way, so you must drive to the next exit to turn around. A step on the motorway costs **half** a step.
- **Buildings:** 64 instances of 18 types, each occupying 2×2 cells (the airport is larger). Codes are `100 + type*10 + instance`.

| Type | Count | Type | Count |
|---|---|---|---|
| Supermarket | 7 | Car dealer | 4 |
| Bank | 6 | Playground | 4 |
| Underground station | 6 | Department store | 3 |
| Arms dealer | 5 | Train station | 2 |
| Pub | 5 | Loan shark | 2 |
| Hotel | 5 | Duds Dave (counterfeiter) | 1 |
| Casino | 5 | Police HQ | 1 |
| Villa | 5 | Harbour | 1 |
| | | City hall | 1 |
| | | Airport | 1 |

- **Step budget:** 25 on foot, 27–46 by car (§6.3). Entering a building costs steps depending on how long you stay. **[TBD]** Cost per action.
- **Fast travel:** underground (any station to any station, price scales with gang size), train (between the two stations).
- **Police checks** can trigger while walking or driving (§8).
- **[new]** We keep the original layout as the canonical map. It's well balanced and recognisable. Later we can add a second, procedurally varied city as a mode.

## 5. Buildings and actions [orig]

| Building | Actions |
|---|---|
| Car dealer | Buy car (3 models per dealer, the dealer's range varies each game) · Steal a car from the lot (intelligence check; best cars can only be stolen) · Blackmail owner |
| Arms dealer | Buy weapon (stock varies by dealer) · Train men (Strength / Intelligence / Brutality / all, quality level 1..n) · Train escape, child-chase and sneaking minigames |
| Pub | Sell stolen goods (radios, electronics) · Hire gangsters (Crook+) · Get assignments: legal work (skip months for pay), contract killing (fight), blackmail material, suitcase smuggling · *Sell children* (**removed in Caper City**, see §0.3) |
| Hotel | Rent room (needed for some actions; rent paid in advance per month) · Pay rent · Raid hotel (porter may fight back or call friends) |
| Bank | Bank raid (needs suitable weapon; alarm → fight guards) · Crack the safe (night break-in + **safe-cracking minigame**: 3 dials, listen for the different tone, ~8 seconds) · Blackmail bank chief |
| Duds Dave | Buy counterfeit money (exchange real money for a larger amount of fakes; police may detect it) · New passport (1,000 DM each; lowers recognition at police checks) |
| Underground | Pickpocket on platform · Pickpocket in train (better odds) · Travel |
| Police HQ | Free an imprisoned player (they owe you, so it's a negotiation) · Bribe chief constable for N months (no arrests) · Blackmail chief constable |
| Train station | Station pub (the only source of car radios) · Platform pickpocketing · Rob the mail train (**container-pushing minigame** to block the track, then fight the guards) · Take train |
| Casino | Blackjack / poker / roulette (automatic; a high-Intelligence gangster plays; better odds come with lower payouts) · Blackmail owner |
| Playground | *Kidnap a child* (**reworked in Caper City**, see §0.3) · Pickpocket grandmas |
| Supermarket | Raid · Collect protection money (needs status; existing protector may object) · Beg |
| Harbour | Dockland pub · Beach pickpocketing · Steal containers (**push containers onto marked fields, then exit** before time runs out) |
| Loan shark | Borrow up to 30,000 (5%/month, 5-month term; then collectors take cash, then car, then prison) · Repay · Buy the loan business (passive monthly income from invested capital) · Collect debts |
| Department store | Steal electronics (night, **push-goods minigame**) · Rob money transport (**sneak past guards minigame**, then fight) · Blackmail owner |
| Villa | Steal electronics · Kidnap (reworked) · Steal luxury car · Blackmail owner |
| City hall | Blackmail mayor · Kidnap visiting head of state (**sneak minigame**, then ransom) · Raid pay office |
| Airport | Holiday (skip N months; stats rise, energy cap of 35 lifted; destinations: 10 from Wanne-Eickel to Sydney) · Smuggle suitcase (from a pub assignment; sneak past customs) |

Blackmail chain [orig]: buy material from a bartender → they reveal the target (car dealer, casino, bank, department store, villa owner, mayor, chief constable) → visit target → money or a special deal. Sometimes the material is worthless ("the photos show him with his wife").

Ransom chain [orig]: kidnap → choose a drop location anywhere in town and an amount (higher amounts mean more chance of being cheated) → visit the drop on a later turn → maybe a **chase minigame**.

## 6. People, gear and stats [orig]

### 6.1 Gang members
Every person has **Energy (E)**, **Strength (S)**, **Intelligence (I)**, **Brutality (B)** and one weapon. Energy is lost in fights and regenerates each month based on Strength. The normal cap is 35 energy; a holiday lifts the cap.

52 named recruits with fixed stats, price and starting weapon (`gangsters.json`). Prices range from 2,000 to 8,000. Each has a flavour description, and some descriptions lie ("don't be deceived by the descriptions!").

### 6.2 Weapons (`weapons.json`)
| Weapon | Reach | Precision | Effect | Price | Min I | Min B |
|---|---|---|---|---|---|---|
| Hands | arm length | good | harmless | 0 | 0 | 0 |
| Club | arm length | lousy | punchy | 200 | 3 | 4 |
| Baton | arm length | moderate | punchy | 300 | 3 | 3 |
| Knife | arm length | moderate | stabbing | 600 | 5 | 8 |
| Throwing stars | good | lousy | good | 2,000 | 5 | 10 |
| Pistol | medium | moderate | deadly | 4,000 | 10 | 15 |
| Rifle | far | good | deadly | 5,500 | 30 | 25 |
| Machine gun | always | very precise | riddling | 7,500 | 60 | 35 |
| Hand grenades | always | dead certain | shredding | 10,000 | 60 | 40 |

**[TBD]** Map tiers to tiles of reach, hit % and damage (from overlay code). Until then, use: reach tiers 1/3/4/6/∞ tiles, precision tiers 35/45/55/70/85/95 %, effect tiers 1/3/5/7/10/14/20 damage.

### 6.3 Cars (`cars.json`)
17 cars plus "on foot". Each car only affects **steps per turn** (25 → 46) and price (1,800 → 8,200). **[new]** Real brand names are replaced with parody names (trademark risk), for example "Ferruccio 512" and "McLaran F1". Each car gets a distinct top-down sprite.

## 7. Fights [orig]
- Turn-based on a grid battlefield. The attacker is on the left and the defender on the right.
- Sides alternate. Each man either **moves one step** or **attacks in one of 8 directions**. Projectiles fly in a straight line.
- A hit is decided by weapon precision. Damage comes from weapon effect. A man at 0 energy is out.
- You can surrender at any time (ESC), and you keep your energy.
- Opponents: police, guards, bodyguards, shop owners, other players (gang war).
- Tactics the original encourages: put unarmed men in front as shields, and keep out of reach while using long-reach weapons.
- **[new]** In player-vs-player fights, **each player controls their own side live**. Spectators watch both. Add a 20-second per-move timer and an auto-move fallback.

## 8. Police [orig]
- Random checks in the street. Being recognised depends on the "wanted" poster, passports, and carrying counterfeit money.
- When caught, choose one:
  - **Escape:** a real-time maze minigame where you survive 20 seconds against 4 police AI. If you fail, you fight.
  - **Bribe:** the amount scales with rank. Sometimes they take the money and arrest you anyway, and then you fight.
- Lost fight → court → prison for 1–2 months as a beginner, longer at higher ranks. A lawyer becomes available at higher ranks.
- Bribing the chief constable grants immunity for N months.

## 9. Minigames [orig]
All use a 27×20 grid (`levels.json`). They are real-time and keyboard-driven in the original.

| Minigame | Levels | Goal |
|---|---|---|
| Police escape (`FLUCHT`) | 8 | Survive 20 s in a maze with 4 pursuing cops |
| Harbour containers (`CONTI`) | 10 | Sokoban-style: push containers onto fields, then reach the exit before time runs out |
| Mail train (`ZUG`) | 9 | Push 8–12 containers onto the track before the train arrives |
| Sneak past guards (`SCHL`) | 9 | Reach the door unseen; guards patrol fixed routes and see forward and to the sides |
| Store theft (`DIEBST`) | 9 | Push goods onto fields at night, then leave |
| Safe cracking | — | Three dials; find the odd tone on each; ~8 s |
| Child chase (`LAB.DAT` sizes) | — | Catch the runner in a maze (**reworked**) |

**[new]** Touch controls: swipe or virtual D-pad, with large tap targets. The minigames are the best spectator moments, so they get the most visual polish.

## 10. Multiplayer design [new]

### 10.1 Requirements (from the owner)
- **Live turns.** Everyone is online in the same session at the same time.
- **Spectating.** While you play, your friends see exactly what you see, live, but can't act until their turn.
- **Platforms:** iOS, Android, desktop (and web for free, since Godot exports there too).

### 10.2 Architecture
```
 ┌──────────── clients (Godot 4, phone / desktop / web) ────────────┐
 │  Presentation (scenes, art, animation, touch UI)                  │
 │  Rules engine (shared GDScript, used for prediction & replays)    │
 └──────────────▲───────────────────────────────▲────────────────────┘
                │ WebSocket (wss)               │
 ┌──────────────┴───────────────────────────────┴────────────────────┐
 │  Game server: headless Godot 4 export, same rules engine          │
 │  • authoritative state per room   • seeded RNG (server-only)      │
 │  • broadcasts every event to all room members                     │
 └───────────────────────────────────────────────────────────────────┘
```
- **One codebase.** The rules engine is plain GDScript classes (no nodes) under `game/rules/`. The server and the clients run the same code.
- **The server is authoritative.** Clients send *intents* ("move north", "choose action 2", "push left"). The server validates them, resolves all randomness with its own seeded RNG, and broadcasts *events*.
- **Spectating comes for free.** Every event goes to every client in the room. The active player's screen is a pure function of the event stream, so spectators render the identical view. A "follow" camera mirrors the active player's camera.
- **Real-time minigames.** The server runs the simulation at a fixed tick (20 Hz). The active player gets input prediction, and spectators get an interpolated stream. Each minigame is deterministic given seed + inputs, which also gives us replays.
- **Transport:** WebSocket, because it works on every export target including web. Godot's `WebSocketMultiplayerPeer` or a thin JSON/MsgPack protocol of our own. **Recommended:** our own protocol, which is easier to test and version.
- **Rooms:** 2–4 players, joined with a 6-letter room code or invite link. A lobby with ready checks. The host picks the target score.
- **Reliability:** any player can reconnect and resume (the server keeps state and sends a snapshot plus later events). Turn timer (default 4 min for the town phase), AFK auto-skip, and a vote-kick.
- **Persistence:** room state is saved to disk or a database after every event, so a server restart doesn't lose the game. Players can also leave and resume the next day (the original had save and load).
- **Hosting:** runs on the owner's existing hosting provider. **[TBD]** The server needs a long-running process with WebSocket support (a VPS or container host). Ordinary shared web hosting won't work.

### 10.3 Things multiplayer adds that the original couldn't
- Spectator reactions (emoji, short text chat). These are fun during minigames.
- Live private negotiation: "free me from prison and I'll pay you X". The original left this to players at the same table.
- PvP fights where both sides are controlled live (§7).
- Bots fill empty seats, using simple utility AI.

## 11. Improvements [new]
1. **Content:** see §0.3.
2. **Names:** all fictional (§0.1).
3. **Economy:** retuned in our own balance sheet, using the original's ranges as a reference.
4. **Quality of life:** route preview with step cost, building info on long-press, undo before confirming movement, a minimap with filters (the original had this).
5. **Pacing:** turn timer, faster animations, option to skip title cards ("only new" option from the original).
6. **Balance pass** once formulas are recovered. Keep the original's odds as the default ruleset ("Classic") and allow a tuned ruleset ("Remastered").
7. **Accessibility:** colour-blind-safe markers, scalable text, and minigame difficulty assists.

## 12. Art direction [new]
- **Top-down 2D** (see §0.4): gritty crime with comic exaggeration.
- **A new city**, about the same size (around 45×40 cells), with new districts: Old Town, Harbor, Midtown, Hillside villas, and the airport. 18 building types at 2×2 cells, drawn at 128 px per cell.
- Road tiles: a new tileset using Godot `TileMapLayer` terrain autotiling.
- Characters: top-down crew members with 8-direction walk; cars with rotating sprites.
- Placeholders are our own simple shapes (like the canvas), never original art.

## 13. Godot project layout (planned)
```
game/
  rules/          # pure GDScript: state, actions, RNG, fight, economy, police
  data/           # JSON tables (from extraction/), editable
  net/            # protocol, client session, server room manager
  scenes/         # town, building menus, fight, minigames, lobby, overview
  server/         # headless entry point
  tests/          # GUT/gdUnit tests of rules against recorded originals
extraction/       # tools + output from the DOS game (this phase)
docs/             # this document, protocol spec
```

## 14. Open items
| # | Item | How we'll resolve it |
|---|---|---|
| 1 | Crime success formulas, payouts, police check odds, prison length, fight hit/damage math, energy regen | Disassemble overlay code (DOSBox-X debugger + Ghidra), confirm by playing |
| 2 | Rank thresholds vs target score | Same |
| 3 | Step cost of each building action | Same |
| 4 | Meaning of the 14 level parameters (start, actors, time) | Partially known; confirm while porting minigames |
| 5 | Hosting provider specifics | Owner to confirm (VPS/container with WebSockets?) |
| 6 | GitHub repo for the project | Owner to create and connect |
