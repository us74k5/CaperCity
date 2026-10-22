class_name Casino
extends RefCounted
## The casino's games, played for real so they can be shown: actual blackjack hands, poker hands and
## roulette spins. The server decides win or lose first (keeping the game's odds; a smart gangster
## does a little better), then deals a game that comes out that way. The deal goes into the result
## so every client plays the same hand out on the table.
## A card is [rank 1..13, suit 0..3]; suits 0/1 are black (spades, clubs), 2/3 red (hearts, diamonds).

const TABLES := {"blackjack": [0.46, 2], "poker": [0.31, 3], "roulette": [0.15, 6]}   # base win chance, payout multiple
const RANKS := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS := ["♠", "♣", "♥", "♦"]
const HANDS := ["High card", "One pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"]
# A European wheel, pocket by pocket.
const WHEEL := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]


static func win_chance(game: String, smarts: int) -> float:
	return float(TABLES[game][0]) + (smarts - 50) / 1000.0


## A game of `game` that ends in a win (or not) for the player.
static func deal(game: String, win: bool, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in 400:
		var g: Dictionary
		match game:
			"blackjack":
				g = _blackjack(rng)
			"poker":
				g = _poker(rng)
			_:
				g = _roulette(rng)
		if g.outcome == ("win" if win else "lose"):
			g.game = game
			return g
	return {"game": game, "outcome": "win" if win else "lose"}


static func card_name(c: Array) -> String:
	return RANKS[int(c[0])] + SUITS[int(c[1])]


static func is_red(c: Array) -> bool:
	return int(c[1]) >= 2


static func color_of(n: int) -> String:
	return "green" if n == 0 else ("red" if n in REDS else "black")


# ------------------------------------------------------------------ blackjack

static func _blackjack(rng: RandomNumberGenerator) -> Dictionary:
	var deck := _deck(rng)
	var you: Array = [deck.pop_back(), deck.pop_back()]
	var house: Array = [deck.pop_back(), deck.pop_back()]
	while total(you) < 17:
		you.append(deck.pop_back())
	var outcome := ""
	if total(you) > 21:
		outcome = "lose"
	else:
		while total(house) < 17:
			house.append(deck.pop_back())
		if total(house) > 21 or total(you) > total(house):
			outcome = "win"
		elif total(you) < total(house):
			outcome = "lose"
		else:
			outcome = "push"
	return {"you": you, "house": house, "you_total": total(you), "house_total": total(house), "outcome": outcome}


## Blackjack total: face cards count 10, an ace 11 unless that would bust.
static func total(hand: Array) -> int:
	var t := 0
	var aces := 0
	for c in hand:
		var r := int(c[0])
		t += mini(r, 10) if r > 1 else 11
		aces += int(r == 1)
	while t > 21 and aces > 0:
		t -= 10
		aces -= 1
	return t


# ------------------------------------------------------------------ poker (five-card showdown)

static func _poker(rng: RandomNumberGenerator) -> Dictionary:
	var deck := _deck(rng)
	var you: Array = []
	var house: Array = []
	for i in 5:
		you.append(deck.pop_back())
		house.append(deck.pop_back())
	var a := score(you)
	var b := score(house)
	var outcome := "push"
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			outcome = "win" if a[i] > b[i] else "lose"
			break
	return {"you": you, "house": house, "you_hand": HANDS[a[0]], "house_hand": HANDS[b[0]], "outcome": outcome}


## [category, tie-breakers...]; compare element by element. Aces are high (and low in A-2-3-4-5).
static func score(hand: Array) -> Array:
	var ranks: Array = []
	var suits := {}
	for c in hand:
		ranks.append(14 if int(c[0]) == 1 else int(c[0]))
		suits[int(c[1])] = true
	ranks.sort()
	ranks.reverse()
	var counts := {}
	for r in ranks:
		counts[r] = int(counts.get(r, 0)) + 1
	# Ranks ordered by how many of each, then by rank.
	var groups: Array = counts.keys()
	groups.sort_custom(func(x, y): return counts[x] > counts[y] or (counts[x] == counts[y] and x > y))
	var flush := suits.size() == 1
	var straight := counts.size() == 5 and (int(ranks[0]) - int(ranks[4]) == 4 or ranks == [14, 5, 4, 3, 2])
	var high: int = 5 if ranks == [14, 5, 4, 3, 2] else int(ranks[0])
	if straight and flush:
		return [8, high]
	var shape: Array = []
	for g in groups:
		shape.append(counts[g])
	if shape[0] == 4:
		return [7] + groups
	if shape == [3, 2]:
		return [6] + groups
	if flush:
		return [5] + ranks
	if straight:
		return [4, high]
	if shape[0] == 3:
		return [3] + groups
	if shape == [2, 2, 1]:
		return [2] + groups
	if shape[0] == 2:
		return [1] + groups
	return [0] + ranks


# ------------------------------------------------------------------ roulette (a six-number line, pays 6x)

static func _roulette(rng: RandomNumberGenerator) -> Dictionary:
	var first := 1 + 3 * rng.randi_range(0, 10)   # the line covers first..first+5
	var n := rng.randi_range(0, 36)
	var inside := n >= first and n <= first + 5
	return {"line": first, "number": n, "color": color_of(n), "pocket": WHEEL.find(n), "outcome": "win" if inside else "lose"}


static func _deck(rng: RandomNumberGenerator) -> Array:
	var deck: Array = []
	for s in 4:
		for r in range(1, 14):
			deck.append([r, s])
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	return deck
