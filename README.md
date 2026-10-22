# Caper City

Rival crews, one town, live turns. An online multiplayer crime game for phones and desktop, built with **Godot 4.7**.
Inspired by the 1993 DOS game *Crime Fighter*; all names, art, text and the city are our own.

Design: [`docs/DESIGN.md`](docs/DESIGN.md)

## Play the current build

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET).
2. Open Godot → **Import** → pick this folder's `project.godot` → **Import & Edit**.
3. Press **F5** (Run Project).

### Test alone
On the title screen press **Solo test**. You get your crew plus a local rival on the same device, and you play both turns.

### Test with friends (same Wi-Fi)
- One person presses **Host a game**. The lobby shows their address, e.g. `192.168.1.20`.
- Everyone else types that address and presses **Join**.
- The host picks a game length and presses **Start the game**.
- If friends can't connect, allow Godot through the host computer's firewall (port **7777**, TCP).

### Test with two windows on one computer
In the Godot editor: **Debug → Customize Run Instances…** → enable multiple instances, set **2**, run. Host in one window, join `127.0.0.1` in the other.

### Run a dedicated server (for your hosting later)
```
godot --headless --path . -- --server --port=7777
```
The first player to join becomes the room host. The server needs a host that keeps a process running and accepts WebSocket connections on that port.
A dedicated server is one room. Anyone who arrives while a game is running joins it with a new crew (up to 6), and a
player who drops out has their turns skipped until they come back on the same device, which hands them their crew again.
The room host can end the game for everyone (back to the lobby); it also goes back to a fresh lobby once no player is left.
If the player whose turn it is goes quiet for 60 seconds (a frozen tab, a dead phone connection), everyone else gets a
**Skip their turn** button. The server logs joins, turns, prompts and refused actions: `journalctl -u capercity`.

### Play in a browser (the online server)
`deploy/deploy.sh root@SERVER --setup` exports the Web build and a headless Linux server, installs nginx, a
Let's Encrypt certificate (acme.sh; Godot's web build only runs over HTTPS) and a `capercity` systemd service on the server, and uploads both (later deploys: drop `--setup`; a deploy restarts the
server and ends any game in progress). Players open `https://SERVER/` and press **Play**; nginx serves the page and
proxies `/ws` to the game server on port 7777. Desktop builds can still join with the server's address.
Phones get a larger, tighter layout and a "turn sideways" prompt in portrait; Android goes fullscreen and landscape on the first tap.
Force a layout with `?mobile=1` or `?desktop=1` in the URL (or `-- --mobile` when running from Godot).

## Controls
- **Make your boss:** in the lobby (or straight after joining a game under way) pick a character with the arrows and roll
  each stat on its own button: Muscle, Smarts, Nerve, Stamina and your starting bankroll. Each stat rolls once, and you
  get 3 re-rolls to spend on any of them (a re-roll can go either way). Characters will get their own perks later.
  The host can start before everyone is done; whatever's left is picked for them.
- **Music:** the title screen's Music button, or **M** in game, turns the background music on or off (remembered).
- **Look around:** drag the map with the left or right mouse button (or a finger). Dragging never moves your crew;
  **Centre** (or Space) goes back to whoever's turn it is.
- **Move:** tap anywhere on the map (or a building) to walk there, or use arrow keys / WASD / the on-screen arrows.
- **Enter a building:** walk into it. The view switches to a street-level scene of that place, like the original; pick actions from the menu on the right.
- **The arms dealer:** a gun store you walk into. "Train your crew" takes you to the gym out back; your crew's stats
  show beside the menu there and when you pick who gets a weapon (with what each of them still needs).
- **The casino:** walk in and you're inside. Click a table (blackjack, poker, roulette) to sit down, then a chip to bet; the hand is dealt or the wheel spun on the table.
- **Minigames:** arrow keys / WASD / the on-screen pad. In chases you keep running until you turn (press turns early);
  in the sneaking and pushing games each press is one step (hold to repeat). The safe: up/down turns a dial, left/right or 1/2/3 picks one.
- **Mouse wheel / pinch:** zoom.
- **Leave a game:** the **×** in the top-right corner (or Esc) takes you back to the title screen. The room host also gets
  **End the game for everyone** there, and **New game** when a game is won.
- **The motorway:** with a car, each cell costs half a step (the banner shows e.g. "11½ steps left"). Lanes run one way; turn at an exit.

## What's in version 0.1
- Online lobby (host/join over WebSockets), local seats for hot-seat testing, dedicated server mode.
- Live spectating: everyone sees the active player's moves, menus, prompts and results as they happen.
- The original town, cell for cell: 64 buildings of 18 types, the same roads and the motorway ring.
  Each motorway lane runs one way, needs a car and costs half a step per cell, as in the original.
- Turns with a step budget, months, rent, loans, jail, holidays, ranks, and the race to Boss of Caper City.
- Every building's actions: buying and stealing cars, weapons, training, hiring crew, robberies, bank jobs,
  safe cracking, the mail train, containers, electronics, protection rackets, blackmail, hit jobs,
  kidnapping with ransom drops, the casino, the subway and trains, the print shop, bribing the police chief and bailing out rivals.
- Police checks on their own screen (a random stop while walking happens at most once a turn; heat makes it likelier) (squad car, officers, siren bar): make a run for it, bribe them, or shoot it out.
  Running for it is a real-time maze chase, as in the original: four cops close in and you must stay free for 20 seconds.
  A crime that goes wrong skips the standoff and goes straight to the chase. One crime a visit: once it has played out
  (pulled off, or you got away) you're back on the street, and walking back in means arrest.
  Your runner moves on your own screen the instant you press a key; the server checks each step.
  The response fits what they caught you at, or what they find on you: one or two beat cops (slow to chase) for a
  pickpocket or up to 5 stolen devices, four or five for a robbery, a stolen car or 6-10 devices, and the full squad
  (eight officers, nearly as fast as you) for a kidnapping or more than 10 devices. Bribes cost more and work less often
  for big crimes. Getting caught, a double-crossing cop or a shootout leads to a fight; losing means court and jail.
  Jail impounds your car, takes your crew's weapons and stolen goods and costs a $500 fine. Fresh out of jail with
  nothing on you, a checkpoint lets you go. The cops watch every building you've hit: walk back into one and you're
  arrested on the spot (a paid-off police chief still covers you).
- The ransom chase: when the parents cheat, catch the runaway with the money case in 15 seconds.
- The original's other real-time minigames, each with fresh levels every time:
  sneaking past guards (armored truck, the dignitary, villa break-ins, smuggling a suitcase through airport customs),
  pushing goods or containers onto the truck's squares and getting out in time (department store, villas, the docks),
  blocking the track for the mail train (then fighting its guards), and cracking the bank vault's three dials by ear.
  Practise escaping, catching and sneaking at an arms dealer.
- Turn-based street fights, as in the original: your crew on the left, theirs on the right. Each man steps one square
  or attacks in a straight line (8 directions); weapon reach, aim and damage matter, and shots hit the first man in the way.
  Tap a teal square to step or a red ring to attack, or press Auto-fight / Give up. Used for police, failed crimes,
  hit jobs, turf wars and gang wars (the defending crew is played by the computer for now).

**Not yet:** live PvP control in gang wars (the defender is computer-played), lawyers.

## Art
The city is 3D, built from Kenney's City Kits (Commercial, Industrial, Suburban, Roads), Car Kit and Mini Characters, CC0, www.kenney.nl.
Every car (the lot, players' cars on the map, squad cars, traffic) is a Car Kit model, see `scripts/ui/car_models.gd`.
The models live in `assets/models/` with each kit's license. Each player is an animated character on a disc of their color
(walking, idling, or driving once they own a car). Officers stand outside Police HQ and townsfolk idle by some buildings.
Cars and water are simple shapes made in code.

## Tests
```
godot --headless --path . --script res://tests/soak_test.gd       # 40 random 3-player games, checks for broken states
godot --headless --path . --script res://tests/city_map_test.gd   # the original map and its movement rules
godot --headless --path . --script res://tests/creation_test.gd   # making your boss, and how often police stop you
godot --headless --path . --script res://tests/jail_test.gd       # jail, crime scenes, loan collectors, police response by crime, chase steps
godot --headless --path . --script res://tests/ui_lot_test.gd     # the car lot, and the camera in among the cars when stealing one
godot --headless --path . --script res://tests/ui_creator_test.gd   # the creator, dragging the map, the gun store and gym
godot --headless --path . --script res://tests/ui_smoke_test.gd   # drives the real menus/HUD through a game
godot --headless --path . --script res://tests/ui_fight_test.gd   # police stop -> shoot it out -> fight played by tapping
godot --headless --path . --script res://tests/ui_place_test.gd   # walks into every building type and checks its scene
godot --headless --path . --script res://tests/ui_minigame_test.gd   # plays every minigame through the HUD
godot --headless --path . --script res://tests/ui_casino_test.gd   # sits at each casino table, bets, watches the hand
godot --headless --path . --script res://tests/minigame_balance_test.gd   # bots play chases, prints win rates
# chase over the network (two processes):
godot --headless --path . --script res://tests/net_chase_host.gd & godot --headless --path . --script res://tests/net_chase_client.gd
```
Room test: `tests/net_room_test.sh [godot]` (joining a running game, getting your crew back, ending the game).
Fight test: `tests/net_fight_test.sh [godot] [--how=run] [--midfight] [--stall]` (a networked player who dropped out
and came back plays a police fight through the real HUD; `--stall` freezes at the stop and the other player skips the turn).
Network test: start a dedicated server (`-- --server --port=7790`), then run `tests/net_client_test.gd`
twice (`-- --name=Ana --start` and `-- --name=Bo`). Each client plays its own turns and watches the other's.

## Layout
```
scripts/rules/   game rules (pure GDScript, no nodes): balance tables, city generator, GameServer
scripts/net/     Net autoload: WebSocket server/client, state broadcast
scripts/ui/      menus, lobby, 3D city renderer, HUD
assets/models/   Kenney City Kit models (GLB) and their licenses
tests/           headless tests
tools/extraction reference tools for the 1993 game's files (not part of the game)
docs/            design document
```

## License
Proprietary, all rights reserved. See [LICENSE](LICENSE).
