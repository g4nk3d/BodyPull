--[[ Body Pull - Game/Rooms_Emberdeep.lua
	Delve 4: Emberdeep Forge. Lava burns you for 1 each turn you end on it (mobs never step there),
	mixed packs, and everything learned so far.

	Map key: as Candlewick, plus  ^ lava
	          w Cinderguard dwarf   f fire-caster (caster)   m magma hound (elite, fast)
	          K Forgemaster Thane Kolgrim (elite boss: moves only while he can see you) ]]

local _, ns = ...
ns.Rooms = ns.Rooms or {}
local list = ns.Rooms

local function Room(t)
	t.delve = "emberdeep"
	list[#list + 1] = t
end

Room {
	id = "ed01", name = "The Cooling Channel",
	gold = 21, par = 26, solution = "NNEEEEEENNSWWSSWWSNSN",
	hint = "Lava burns you for one each turn you end on it, but nothing will follow you across.",
	map = {
		"#############",
		"#.....^.....#",
		"#.....^..w..#",
		"#.....^.....#",
		"#...........#",
		"#.....^.....#",
		"#.....^..w..#",
		"#@CC..^.....#",
		"#.CC..^.....#",
		"#############",
	},
}

Room {
	id = "ed02", name = "Hound Kennels",
	gold = 31, par = 38, solution = "NNNEEEENNWEEEEWSSSSSWWWSWWWNNSN",
	hint = "Magma hounds are elite and fast. One at a time, or not at all.",
	map = {
		"#############",
		"#.m.......m.#",
		"#...........#",
		"#.###...###.#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed03", name = "Fire Watch",
	gold = 12, par = 15, solution = "NNNEESSWNWSE",
	hint = "A fire-caster behind a lava moat. Make him walk round it to reach you.",
	map = {
		"#############",
		"#...........#",
		"#.^^^^^^^^^.#",
		"#.^...f...^.#",
		"#.^.......^.#",
		"#.^^^^.^^^^.#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed04", name = "The Anvil Line",
	gold = 17, par = 21, solution = "NNNNSSSSN..EEWWES",
	hint = "Dwarves at their anvils, chained in pairs.",
	links = { { 1, 2 }, { 3, 4 } },
	map = {
		"#############",
		"#.w.%...%.w.#",
		"#.w.......w.#",
		"#...........#",
		"#....O.O....#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed05", name = "Slag Bridges",
	gold = 18, par = 22, solution = "NNEEENNESSSSWSWWNN",
	hint = "Two bridges over the lava. Hounds take the one closest to you.",
	map = {
		"#############",
		"#.....m.....#",
		"#...........#",
		"#^^^.^^^^.^^#",
		"#^^^.^^^^.^^#",
		"#...........#",
		"#.....w.....#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed06", name = "Bellows Hall",
	gold = 27, par = 33, solution = "NNNNNEEEEEESSSSSWWWWWW.N.EE",
	hint = "Two casters, one pillar. Stand where only one can see you.",
	map = {
		"#############",
		"#.f.......f.#",
		"#...........#",
		"#.....O.....#",
		"#...........#",
		"#...w...w...#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed07", name = "The Crucible",
	gold = 17, par = 21, solution = "NNNNESSSSNWEESWNE",
	hint = "A mixed pack around the crucible. Burn a turn on the lava to break their line.",
	links = { { 1, 2, 3 } },
	map = {
		"#############",
		"#...........#",
		"#...w.f.w...#",
		"#...........#",
		"#^^^^^.^^^^^#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed08", name = "Chain Lift",
	gold = 26, par = 32, solution = "NSEENNNNEEESESSWWWWWW...EE",
	hint = "Hound and caster share a ledge. The hound will reach you first: be on the rug.",
	map = {
		"#############",
		"#.m.....f...#",
		"#...........#",
		"#^^^^^^^^^.^#",
		"#...........#",
		"#.w.........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed09", name = "Ember Vault",
	gold = 27, par = 33, solution = "EEEWN.NNENNEEESSSSWWWWWW.EE",
	hint = "A hound, a dwarf and a caster split by lava. Everything at once, unless you're patient.",
	map = {
		"#############",
		"#.w...^...f.#",
		"#.....^.....#",
		"#..O..^..O..#",
		"#...........#",
		"#.m.........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "ed10", name = "The Forgemaster",
	gold = 25, par = 30, solution = "NEEEEEEWNNSSWWWWWESNWSNEE",
	hint = "Kolgrim moves only while he can see you. Break his sight and he stands like stone.",
	map = {
		"#############",
		"#.....K.....#",
		"#...........#",
		"#..O.....O..#",
		"#...........#",
		"#.w.......f.#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}
