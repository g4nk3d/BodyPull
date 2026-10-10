--[[ Body Pull - Game/Rooms_Candlewick.lua
	Delve 1: Candlewick Mine. Teaches aggro rings, linked packs and the healer's sight line.

	Map key:  # wall   . floor   O pillar (blocks walking and sight)   % a low prop: barrel, crate or ore
	          cart (blocks walking, not sight)   C the party's 2x2 rug   @ entrance (the tank starts here)
	          d kobold digger   g kobold geomancer (caster)   r tunnel rat (fast)   G Foreman Grizzlebeard
	Mobs are numbered in reading order (left to right, top to bottom) for links and ring overrides.
	gold / par / solution come from tools/solve.lua (breadth-first, every move); gold is the best
	possible step count and par leaves room for a clean but not perfect pull. ]]

local _, ns = ...
ns.Rooms = ns.Rooms or {}
local list = ns.Rooms

local function Room(t)
	t.delve = "candlewick"
	list[#list + 1] = t
end

Room {
	id = "cw01", name = "The Lantern Door",
	gold = 14, par = 17, solution = "NEEEEEENWWWWNS",
	hint = "Step into the kobold's ring, then lead him into the green party ring around the rug.",
	map = {
		"#############",
		"#...........#",
		"#.CC.....d..#",
		"#.CC........#",
		"#@..........#",
		"#############",
	},
}

Room {
	id = "cw02", name = "Two Candles",
	gold = 19, par = 23, solution = "NNNEEEESEENESWWWNSS",
	hint = "Pull one kobold at a time: walk where only one ring reaches.",
	map = {
		"#############",
		"#.....#.....#",
		"#..d..#..d..#",
		"#.....#.....#",
		"#.....O.....#",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}

Room {
	id = "cw03", name = "The Chain",
	gold = 22, par = 27, solution = "NNEENNEEEESSWWWWWWESNE",
	hint = "The chained pair wakes together. Take the loner first.",
	links = { { 2, 3 } },
	map = {
		"#############",
		"#..d........#",
		"#.......d.d.#",
		"#...........#",
		"###.###.#####",
		"#...........#",
		"#.CC........#",
		"#@CC........#",
		"#############",
	},
}

Room {
	id = "cw04", name = "Behind the Prop",
	gold = 12, par = 15, solution = "NNNNEESSSSEN",
	hint = "A geomancer casts while it can see you. Duck behind the pillar and make it come to you.",
	map = {
		"#############",
		"#.....g.....#",
		"#...........#",
		"#.....O.....#",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}

Room {
	id = "cw05", name = "Rat Run",
	gold = 28, par = 34, solution = "NNNNEESESESENNNNNEEEWWSSSSSS",
	hint = "Rats run two steps a turn, but one blow kills them.",
	map = {
		"#############",
		"#r.........r#",
		"#.###...###.#",
		"#...........#",
		"#.....d.....#",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}

Room {
	id = "cw06", name = "The Split Shaft",
	gold = 28, par = 34, solution = "NNENNSSEESNSNEEENNNSSSWWWWSN",
	hint = "Two shafts, two packs. Brother Aldous can't heal you around the corner.",
	links = { { 1, 2 } },
	map = {
		"#############",
		"#.d.g.#.....#",
		"#.....#..d..#",
		"#.....#.....#",
		"##.####.....#",
		"#.......##.##",
		"#.CC........#",
		"#@CC........#",
		"#############",
	},
}

Room {
	id = "cw07", name = "Ore Cart Alley",
	gold = 21, par = 26, solution = "NNNEEENEEEESSWWWWSSNN",
	hint = "Carts stop feet, not eyes. Kobolds will see you over them.",
	map = {
		"#############",
		"#..d..%..d..#",
		"#.....%.....#",
		"#.%.......%.#",
		"#.....g.....#",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}

Room {
	id = "cw08", name = "The Narrows",
	gold = 20, par = 24, solution = "NNEEEENNNSSSWWSNSSEW",
	hint = "In a corridor the pack lines up. Only the front kobold can reach you.",
	links = { { 1, 2, 3 } },
	map = {
		"#############",
		"#...d.d.d...#",
		"#...........#",
		"#####.#######",
		"#####.#######",
		"#.....#######",
		"#.CC..#######",
		"#@CC..#######",
		"#############",
	},
}

Room {
	id = "cw09", name = "Geomancer Gallery",
	gold = 24, par = 29, solution = "NNEENNEEEEEESSWWWWW.S.NE",
	hint = "Two casters on the balconies. Pull each one around a corner so it has to walk to you.",
	map = {
		"#############",
		"#g...#d#...g#",
		"#....#.#....#",
		"#.O.......O.#",
		"###.#####.###",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}

Room {
	id = "cw10", name = "The Foreman's Office",
	gold = 25, par = 30, solution = "NEEEENNNESSWWESNSSW..EWNN",
	hint = "When Grizzlebeard wakes, every kobold wakes. Clear his crew first, quietly.",
	map = {
		"#############",
		"#.....G.....#",
		"#...........#",
		"#.d.##.##.d.#",
		"#...#...#...#",
		"#.r.#...#.g.#",
		"#...........#",
		"#....CC.....#",
		"#@...CC.....#",
		"#############",
	},
}
