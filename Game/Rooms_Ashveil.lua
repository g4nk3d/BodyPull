--[[ Body Pull - Game/Rooms_Ashveil.lua
	Delve 3: Ashveil Crypt. Teaches fast mobs (ghouls run two tiles), ambush sarcophagi that open when
	you step next to them, and banshees whose wail knocks you a tile back.

	Map key: as Candlewick, plus  k skeleton   h ghoul (fast)   b banshee (caster: a landed wail hits for 1
	          and pushes you one tile away)   a sarcophagus (wakes only when you stand next to it)
	          A the Hollow Abbot (boss: hits for 3) ]]

local _, ns = ...
ns.Rooms = ns.Rooms or {}
local list = ns.Rooms

local function Room(t)
	t.delve = "ashveil"
	list[#list + 1] = t
end

Room {
	id = "av01", name = "Bone Hall",
	gold = 31, par = 38, solution = "NNNENNEEEEEESSESSSWWWWWSWNNSWNE",
	hint = "Skeletons, two by two. Take the near pair first.",
	map = {
		"#############",
		"#.k.......k.#",
		"#...........#",
		"#..O.....O..#",
		"#...........#",
		"#....k.k....#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av02", name = "The Quick and the Dead",
	gold = 26, par = 32, solution = "EEE.NNNNNSSEEEESSWWWWWSNSN",
	hint = "Ghouls run two tiles a turn. You can't outpace them: pick where they catch you.",
	map = {
		"#############",
		"#.....h.....#",
		"#...........#",
		"####.###.####",
		"#...........#",
		"#.h.......h.#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av03", name = "Sarcophagus Row",
	gold = 32, par = 39, solution = "NNNNNEEEEEEEESSWSSWWWWSNWWEWEWES",
	hint = "The coffins open when you step beside them. Walk the middle of the hall.",
	map = {
		"#############",
		"#..a.....a..#",
		"#...........#",
		"#...........#",
		"#.....k.....#",
		"#...........#",
		"#..a.....a..#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av04", name = "The Wailing Gallery",
	gold = 18, par = 22, solution = "NESEENNNESSWWWW.EE",
	hint = "A banshee's wail knocks you back a tile. Don't let it knock you into the pack.",
	links = { { 2, 3 } },
	map = {
		"#############",
		"#.....b.....#",
		"#...........#",
		"#..O.....O..#",
		"#...........#",
		"#.k.......k.#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av05", name = "Cobweb Corridor",
	gold = 29, par = 35, solution = "NNEENNEEEEEESSSSWWWWWSWNNWWES",
	hint = "Ghouls behind coffins. Open a coffin only when you're ready to run.",
	map = {
		"#############",
		"#.h.#...#.h.#",
		"#...#.a.#...#",
		"#...........#",
		"###.##.##.###",
		"#...........#",
		"#.....a.....#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av06", name = "Ossuary",
	gold = 14, par = 17, solution = "NNNNSSESSSEWNN",
	hint = "A chained pack of bones with a ghoul at its tail. The ghoul arrives first.",
	links = { { 1, 2, 3 } },
	map = {
		"#############",
		"#...........#",
		"#..k.k.h....#",
		"#...........#",
		"#.%.%.%.%.%.#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av07", name = "Two Voices",
	gold = 24, par = 29, solution = "NNEENNNEEEWWSSSWWWW.S.NE",
	hint = "Two banshees. Break one's sight while the other's wail is still rising.",
	map = {
		"#############",
		"#.b.......b.#",
		"#...........#",
		"#.....O.....#",
		"#...O...O...#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av08", name = "The Lich Lane",
	gold = 29, par = 35, solution = "NEEEENSWWSWNEEENNNSESSWWWWWES",
	hint = "Coffins line the only path. Every step beside one is a pull.",
	map = {
		"#############",
		"#.....k.....#",
		"#...........#",
		"#####.#.#####",
		"#####a.a#####",
		"#####...#####",
		"#.....a.....#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av09", name = "The Choir Loft",
	gold = 30, par = 36, solution = "NNNNNNESWSSEEEEEEESWWWWWSNSWNN",
	hint = "A banshee sings over the ghouls. Pull the ghouls first, out of her sight.",
	map = {
		"#############",
		"#....b......#",
		"#...........#",
		"#.#########.#",
		"#.h.......h.#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}

Room {
	id = "av10", name = "The Hollow Abbot",
	gold = 25, par = 30, solution = "NNEEENEEESSWWWWWWESNSNSNE",
	hint = "The Abbot hits for three. Draw his guards away before you face him.",
	map = {
		"#############",
		"#.....A.....#",
		"#...k...k...#",
		"#...........#",
		"#..O.....O..#",
		"#...........#",
		"#...........#",
		"#@CC........#",
		"#.CC........#",
		"#############",
	},
}
