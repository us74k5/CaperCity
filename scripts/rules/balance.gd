class_name Balance
## All tunable numbers and names for Caper City. Pure data, no logic.
## Values are our own; ranges were sanity-checked against the 1993 reference game.

const RANKS := [
	"Rookie", "Small Fry", "Hustler", "Operator", "Crew Boss",
	"Big Shot", "Kingpin", "Public Enemy", "Mastermind", "Boss of Caper City",
]
const HIRE_MIN_RANK := 3        # "Operator" and up can hire crew
const PROTECTION_MIN_RANK := 2
const MAX_CREW := 6
const STAMINA_CAP := 35
const STAMINA_CAP_HOLIDAY := 60
const START_CASH := [1500, 4000]
const ROOM_RENT := 400
const LOAN_RATE := 0.05
const LOAN_MONTHS := 5
const LOAN_MAX := 30000
const JAIL_FINE := 500
const PASSPORT_PRICE := 1000
const PLAYER_COLORS := ["#FF5D4F", "#35D0BA", "#F2C230", "#A98BE0", "#7FB3F2", "#F28FC2"]

# Bosses to pick from when creating your character (the model is the id). Each will get its own
# perks on top of the rolled stats; "perk" stays empty until those are designed.
# character-male-c wears a police uniform, so he's not on the list.
const AVATARS := [
	{"id": "character-male-a", "name": "Vinnie", "tag": "The old-school wiseguy", "perk": ""},
	{"id": "character-female-a", "name": "Roxy", "tag": "Talks her way past anyone", "perk": ""},
	{"id": "character-male-b", "name": "Dutch", "tag": "Never forgets a face", "perk": ""},
	{"id": "character-female-b", "name": "Lola", "tag": "Owns the night", "perk": ""},
	{"id": "character-male-d", "name": "Moose", "tag": "Built like a vault door", "perk": ""},
	{"id": "character-female-c", "name": "Sable", "tag": "Counts cards for fun", "perk": ""},
	{"id": "character-male-e", "name": "Slick", "tag": "Gone before the sirens", "perk": ""},
	{"id": "character-female-d", "name": "Ruby", "tag": "Steady hands, cold eyes", "perk": ""},
	{"id": "character-male-f", "name": "Tank", "tag": "Hits first, asks later", "perk": ""},
	{"id": "character-female-f", "name": "Nova", "tag": "Wires, locks and alarms", "perk": ""},
	{"id": "character-female-e", "name": "Jinx", "tag": "Trouble follows her home", "perk": ""},
]
# Character creation: each stat is rolled on its own button; REROLLS more spins to use on any of them.
const ROLL_STATS := {
	"muscle": {"label": "Muscle", "range": [1, 99]},
	"smarts": {"label": "Smarts", "range": [1, 99]},
	"nerve": {"label": "Nerve", "range": [1, 99]},
	"stamina": {"label": "Stamina", "range": [20, 35]},
	"cash": {"label": "Bankroll", "range": [1500, 4000]},
}
const REROLLS := 3

# Cars: steps per turn and price. Index 0 = on foot.
const CARS := [
	{"name": "On foot", "steps": 25, "price": 0},
	{"name": "Puntino", "steps": 27, "price": 1800},
	{"name": "Minnow", "steps": 28, "price": 2100},
	{"name": "Brisa GT", "steps": 30, "price": 2400},
	{"name": "Familia Wagon", "steps": 32, "price": 2800},
	{"name": "Kestrel 320", "steps": 34, "price": 3100},
	{"name": "Baron Sedan", "steps": 36, "price": 3600},
	{"name": "Regent Limo", "steps": 38, "price": 4800},
	{"name": "Stiletto", "steps": 41, "price": 6000},
	{"name": "Vortex 900", "steps": 44, "price": 7200},
	{"name": "Phantom R", "steps": 46, "price": 8500},
]
const STEALABLE_ONLY := [8, 9, 10]   # dealers never sell these; you have to steal them

# Gear (weapons). power = damage per hit (rolled power..2x power), reach = squares a shot or blow travels,
# aim = base chance to hit. smarts/nerve = what a crew member needs to carry it.
const GEAR := [
	{"name": "Bare hands", "price": 0, "power": 1, "reach": 1, "aim": 0.75, "smarts": 0, "nerve": 0},
	{"name": "Club", "price": 200, "power": 2, "reach": 1, "aim": 0.5, "smarts": 3, "nerve": 4},
	{"name": "Baton", "price": 300, "power": 2, "reach": 1, "aim": 0.6, "smarts": 3, "nerve": 3},
	{"name": "Switchblade", "price": 600, "power": 3, "reach": 1, "aim": 0.6, "smarts": 5, "nerve": 8},
	{"name": "Throwing knives", "price": 2000, "power": 4, "reach": 3, "aim": 0.45, "smarts": 5, "nerve": 10},
	{"name": "Pistol", "price": 4000, "power": 6, "reach": 4, "aim": 0.6, "smarts": 10, "nerve": 15},
	{"name": "Rifle", "price": 5500, "power": 8, "reach": 6, "aim": 0.75, "smarts": 30, "nerve": 25},
	{"name": "Machine gun", "price": 7500, "power": 11, "reach": 12, "aim": 0.85, "smarts": 60, "nerve": 35},
	{"name": "Grenades", "price": 10000, "power": 14, "reach": 12, "aim": 0.95, "smarts": 60, "nerve": 40},
]
const PISTOL := 5
const RIFLE := 6
const MACHINE_GUN := 7
const WHEELCHAIR_STEPS := 15     # a turn's steps on wheels (no motorway, no car unless someone else drives)
const RELEASE_STAMINA := 10      # energy lost to a stretch in jail
const LEGS_STAMINA := 25         # energy lost for good when Eddie's boys break your legs

# Building types. count = how many in the city (as on the original map, see CityMap). color = roof color. sign = rooftop sign.
const BUILDINGS := {
	"car_dealer": {"label": "Car Dealer", "count": 4, "color": "#4F7BC4", "sign": "AUTOS"},
	"arms": {"label": "Arms Dealer", "count": 5, "color": "#6E5A3C", "sign": "GUNS"},
	"pub": {"label": "Pub", "count": 5, "color": "#8C4A2F", "sign": "PUB"},
	"hotel": {"label": "Hotel", "count": 5, "color": "#5C7F6E", "sign": "HOTEL"},
	"bank": {"label": "Bank", "count": 6, "color": "#CDBB8C", "sign": "BANK"},
	"print_shop": {"label": "Print Shop", "count": 1, "color": "#7A6F8F", "sign": "PRINT"},
	"subway": {"label": "Subway", "count": 6, "color": "#3E5C7A", "sign": "METRO"},
	"police": {"label": "Police HQ", "count": 1, "color": "#2F4A8C", "sign": "POLICE"},
	"station": {"label": "Train Station", "count": 2, "color": "#8A8F98", "sign": "RAIL"},
	"casino": {"label": "Casino", "count": 5, "color": "#A13C5A", "sign": "CASINO"},
	"playground": {"label": "Playground", "count": 4, "color": "#3E7A4C", "sign": ""},
	"supermarket": {"label": "Supermarket", "count": 7, "color": "#B4553D", "sign": "MART"},
	"harbor": {"label": "Harbor", "count": 1, "color": "#2C6E8F", "sign": "DOCKS"},
	"loan_shark": {"label": "Easy Eddie's Loans", "count": 2, "color": "#9A7B2F", "sign": "LOANS"},
	"dept_store": {"label": "Department Store", "count": 3, "color": "#5D6F92", "sign": "MEGAMART"},
	"villa": {"label": "Villa", "count": 5, "color": "#C9C3B4", "sign": ""},
	"city_hall": {"label": "City Hall", "count": 1, "color": "#B9A77A", "sign": "CITY HALL"},
	"airport": {"label": "Airport", "count": 1, "color": "#9AA3AE", "sign": "AIRPORT"},
}

const NAME_PREFIX := {
	"car_dealer": ["Lucky Lou's", "Sunset", "Big Wheel", "Chrome Kings"],
	"arms": ["Iron Mike's", "Bullseye", "Surplus Sal's", "Hard Target", "Lock & Load"],
	"pub": ["The Rusty Anchor", "Shady Rest", "The Crooked Mile", "Last Chance Saloon", "The Drowned Rat"],
	"hotel": ["Hotel Majestic", "Starlite Motel", "The Grand Palms", "Harbor Inn", "The Royale"],
	"bank": ["First Harbor Savings", "Caper Trust", "Goldvault Bank", "Union Mutual", "Pinnacle Bank", "Riverside Credit"],
	"print_shop": ["Pressman Pete's"],
	"subway": ["Central", "Old Town", "Midtown", "Harborside", "Hillside", "Market St"],
	"police": ["Caper City PD"],
	"station": ["Union Station", "North Terminal"],
	"casino": ["Golden Ace", "Lucky Seven", "The Velvet Room", "Diamond Palace", "Lady Luck"],
	"playground": ["Sunny Park", "Maple Playground", "Riverside Park", "Oak Hill Park"],
	"supermarket": ["Quik-Mart", "Value King", "FreshCo", "Corner Grocer", "Big Basket", "Daily Deals", "Penny Pincher"],
	"harbor": ["Harbor Docks"],
	"loan_shark": ["Easy Eddie's", "Easy Eddie's Uptown"],
	"dept_store": ["Megamart", "Parkview Galleria", "Hartley's"],
	"villa": ["Villa Bellamy", "The Kingsley Estate", "Casa Monte", "Ashford Manor", "Rosewood Hall"],
	"city_hall": ["City Hall"],
	"airport": ["Caper International"],
}

const FIRST_NAMES := ["Rosa", "Dot", "Lenny", "Priya", "Vic", "Marco", "Tess", "Gus", "Nadia", "Rocco",
	"Frankie", "Ivy", "Sal", "Mags", "Benny", "Kit", "Dmitri", "Lou", "Carmen", "Ozzie", "June", "Ray",
	"Hector", "Bea", "Moe", "Lila", "Stan", "Yuki", "Duke", "Pearl"]
const NICKNAMES := ["Two-Coats", "Knuckles", "the Brain", "Lucky", "Slick", "Fingers", "Tiny", "Ice",
	"the Wrench", "Smokey", "Ace", "Mumbles", "Scarface", "the Kid", "Bullseye", "Jinx", "Hammer", "Whisper"]
const LAST_NAMES := ["Vega", "Kimura", "Mott", "Rao", "Brannigan", "Costa", "Okafor", "Novak", "Russo",
	"Delgado", "Finch", "Moreau", "Kowalski", "Baptiste", "Lindqvist", "O'Hara", "Petrov", "Santos"]

# Pickpocket loot: item, value
const LOOT := [
	["a fake pearl necklace", 0], ["a camera", 120], ["a fat wallet", 500], ["a gold watch", 650],
	["a used handkerchief", 0], ["a pearl necklace", 300], ["a diamond ring", 900], ["a laptop", 1500],
	["a silver ring", 250], ["a stuffed wallet", 950], ["a pack of gum", 1],
]

const HOLIDAYS := [
	{"name": "Lake Weekend", "cost": 600, "boost": 2},
	{"name": "Sunny Coast", "cost": 1200, "boost": 4},
	{"name": "Island Resort", "cost": 2500, "boost": 7},
]
