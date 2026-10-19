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

## Controls
- **Move:** tap anywhere on the map (or a building) to walk there, or use arrow keys / WASD / the on-screen arrows.
- **Enter a building:** walk into it. Pick actions from the menu on the right.
- **Mouse wheel:** zoom.

## What's in version 0.1
- Online lobby (host/join over WebSockets), local seats for hot-seat testing, dedicated server mode.
- Live spectating: everyone sees the active player's moves, menus, prompts and results as they happen.
- A generated city with 57 buildings across 18 types, plus parks, houses and lots.
- Turns with a step budget, months, rent, loans, jail, holidays, ranks, and the race to Boss of Caper City.
- Every building's actions: buying and stealing cars, weapons, training, hiring crew, robberies, bank jobs,
  safe cracking, the mail train, containers, electronics, protection rackets, blackmail, hit jobs,
  kidnapping with ransom drops, the casino, the subway and trains, the print shop, bribing the police chief and bailing out rivals.
- Police checks with bribe / run / shoot-it-out choices; gang wars between players.

**Not yet:** tactical grid fights and the real-time minigames (escape, safe cracking, container pushing, sneaking).
For now those resolve automatically from your crew's stats. Art is placeholder shapes drawn in code.

## Tests
```
godot --headless --path . --script res://tests/soak_test.gd       # 40 random 3-player games, checks for broken states
godot --headless --path . --script res://tests/ui_smoke_test.gd   # drives the real menus/HUD through a game
```
Network test: start a dedicated server (`-- --server --port=7790`), then run `tests/net_client_test.gd`
twice (`-- --name=Ana --start` and `-- --name=Bo`). Each client plays its own turns and watches the other's.

## Layout
```
scripts/rules/   game rules (pure GDScript, no nodes): balance tables, city generator, GameServer
scripts/net/     Net autoload: WebSocket server/client, state broadcast
scripts/ui/      menus, lobby, city renderer, HUD
tests/           headless tests
tools/extraction reference tools for the 1993 game's files (not part of the game)
docs/            design document
```

## License
Proprietary, all rights reserved. See [LICENSE](LICENSE).
