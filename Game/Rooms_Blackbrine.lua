--[[ Body Pull - Game/Rooms_Blackbrine.lua
	Delve 2: Blackbrine Grotto, a flooded smugglers' cave. Teaches water (you can wade, mobs can't)
	and patrols that walk fixed loops.

	Map key: as Candlewick, plus  ~ water (the tank wades through, mobs go around)
	          s smuggler   p powder-bomber (caster)   c shore crab (elite)   I Captain Ilsa Vane (boss)
	patrols = { [mob] = "loop" }: an unaware patrol walks its loop one step a turn (N E S W), back to
	its start; it notices the tank like any sleeper, from wherever it has walked to. ]]

local _, ns = ...
ns.Rooms = ns.Rooms or {}
local list = ns.Rooms

local function Room(t)
	t.delve = "blackbrine"
	list[#list + 1] = t
end

Room {
	id = "bb01", name = "Wet Feet",
	gold = 19, par = 23, solution = "NNNEEEEEENNWWSSSSSS",
	hint = "You can wade through water; smugglers can't. Let him take the long way round.",
	map = {
		"#############",
		"#...........#",
		"#.....~..s..#",
		"#.....~.....#",
		"#.....~.....#",
		"#..CC.~.....#",
		"#@.CC.~.....#",
		"#.....~.....#",
		"#############",
	},
}

Room {
	id = "bb02", name = "The Watchman",
	gold = 21, par = 26, solution = "NEEEEENSWWNNN.SWSSNSN",
	hint = "A patrol walks its loop. Wait until his back is turned, then take him alone.",
	patrols = { [1] = "EEEEEEWWWWWW" },
	map = {
		"#############",
		"#s..........#",
		"#...........#",
		"####.###.####",
		"#....#..s...#",
		"#....#......#",
		"#.CC........#",
		"#@CC........#",
		"#############",
	},
}

Room {
	id = "bb03", name = "Hard Shell",
	gold = 27, par = 33, solution = "NEEEEEENENNNSSWWWWWWSSESNEW",
	hint = "Shore crabs are elite: the party needs four hits. Don't let a smuggler join in.",
	map = {
		"#############",
		"#.........s.#",
		"#..~~~~~....#",
		"#..~...~....#",
		"#..~.c.~....#",
		"#..~...~....#",
		"#..~~.~~....#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "bb04", name = "Powder Keg",
	gold = 10, par = 12, solution = "NEENSSWWNN",
	hint = "The bomber throws from across the water. Get behind the post and make him walk.",
	map = {
		"#############",
		"#...~~~~~...#",
		"#.p.~~~~~...#",
		"#...~~~~~.O.#",
		"#.......~...#",
		"#...~~~~~...#",
		"#.CC~~~~~...#",
		"#@CC~~~~~...#",
		"#############",
	},
}

Room {
	id = "bb05", name = "Crossing Lanterns",
	gold = 15, par = 18, solution = "NEEEENEWSWWWWES",
	hint = "Two patrols cross in the middle. Count their steps.",
	patrols = { [1] = "SSSSSNNNNN", [2] = "NNNNNSSSSS" },
	map = {
		"#############",
		"#...s.......#",
		"#...........#",
		"#.......O...#",
		"#...........#",
		"#...O.......#",
		"#.......s...#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "bb06", name = "The Rope Bridge",
	gold = 19, par = 23, solution = "NNNNEEEESSSWWWWESNE",
	hint = "Only one way across the water for them. Make them queue.",
	links = { { 1, 2, 3 } },
	map = {
		"#############",
		"#...s.s.s...#",
		"#...........#",
		"#~~~~~.~~~~~#",
		"#~~~~~.~~~~~#",
		"#~~~~~.~~~~~#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "bb07", name = "Smugglers' Den",
	gold = 11, par = 14, solution = "NNNESSSEWNN",
	hint = "The pack wakes together, bomber and all. Pull them where he can't see you.",
	links = { { 1, 2, 3 } },
	map = {
		"#############",
		"#....#......#",
		"#.s.p#..O...#",
		"#..s.#......#",
		"#....#..~~..#",
		"#.......~~..#",
		"#.CC........#",
		"#@CC........#",
		"#############",
	},
}

Room {
	id = "bb08", name = "Tide Pools",
	gold = 21, par = 26, solution = "NNNNNEEESSSSWSNWWESNS",
	hint = "Crabs on islands can only reach you by the sand. Wade where they can't follow.",
	map = {
		"#############",
		"#.~~~.c.~~~.#",
		"#.~~~...~~~.#",
		"#...........#",
		"#.~~~.c.~~~.#",
		"#.~~~...~~~.#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "bb09", name = "Lantern Post Watch",
	gold = 18, par = 22, solution = "NNNEEENESSSWWWW.EE",
	hint = "A patrol and a bomber share the dock. Let the patrol pass, then pull the bomber round the post.",
	patrols = { [2] = "EEEEEEWWWWWW" },
	map = {
		"#############",
		"#.......p...#",
		"#..O........#",
		"#...s.......#",
		"#~~~~~.~~~~~#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "bb10", name = "Captain's Cove",
	gold = 23, par = 28, solution = "NNSSNNEEESWWWESNW....ES",
	hint = "Captain Vane walks her deck. When she spots you, her whole crew wakes. Thin the crew while her back is turned.",
	patrols = { [1] = "EEEEESSWWWWWNN" },
	map = {
		"#############",
		"#~~I.....~~~#",
		"#~~......~s~#",
		"#~~......~.~#",
		"#~~~~~.~~~..#",
		"#.s.........#",
		"#.......p...#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}
