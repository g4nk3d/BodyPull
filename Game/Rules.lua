--[[ Body Pull - Game/Rules.lua
	The rules, and nothing else: no frames, no textures, no game API. The same file runs inside the
	game and in the room tools (solver, replay check), so a room behaves identically everywhere.
	Nothing is random: the same moves from the same room always give the same result.

	  R:Parse(room)               a room definition (Rooms_*.lua) -> board (tiles, start, mobs, camp)
	  R:New(board)                the starting state
	  R:Copy(s) / R:Restore(s, c) full snapshot for undo (one table per turn, player-paced)
	  R:Act(board, s, action, ev) one turn: action "N" "E" "S" "W" or "." (wait). Returns false and
	                              changes nothing when the move is blocked (a bump costs no turn).
	                              ev (optional) receives what happened, for the screen and sounds
	  R:InRing(board, m, x, y)    would a sleeping mob notice the tank at (x, y)?
	  R:Sees(board, ax, ay, bx, by) line of sight between tile centres
	  R:HealerSees(board, s)      the healer can reach the tank this turn
	  R:Key(s)                    a compact string of the whole state (solver, replay check)

	A turn: the tank steps (or waits) -> sleeping mobs that see the tank inside their ring wake (a
	linked pack wakes together; a mob that wakes this turn does not act yet) -> the party's DPS hit
	(while the tank is inside the party ring, a mob in the ring) -> every awake mob acts -> 0 pips is a wipe -> the
	healer restores 1 pip if in range and in sight -> no mobs left is a clear. ]]

local _, ns = ...
if type(ns) ~= "table" then ns = {} end
local R = {}
ns.Rules = R

local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min
local concat = table.concat

-- tile codes
local VOID, FLOOR, WALL, PILLAR, PROP, WATER, LAVA = 0, 1, 2, 3, 4, 5, 6
R.T = { VOID = VOID, FLOOR = FLOOR, WALL = WALL, PILLAR = PILLAR, PROP = PROP, WATER = WATER, LAVA = LAVA }
R.MAX_PIPS = 5
R.HEAL_RANGE = 4
R.PARTY_RADIUS = 2.2   -- the party ring: tiles whose centre lies this close to the rug's centre (the rug and one tile around it)

--[[ Mob kinds. ring = aggro radius in tiles; speed = steps per turn; kill = DPS turns to kill;
	hit = melee damage; cast = { range, turns, damage [, fear] } for casters (fear: a landed cast also
	pushes the tank one tile away); family = which mobs a boss calls; callsFamily = waking it wakes its
	whole family; ambush = wakes only when the tank steps next to it (no ring, no sight); statue = moves
	only while it can see the tank; elite = shown as an elite. The board art for each kind is its
	`art` (Data/Atlas.lua animations "<art>_<state>"). ]]
R.KINDS = {
	digger     = { art = "kobold_digger",    ring = 2, speed = 1, kill = 2, hit = 1, family = "kobold", name = "Kobold Digger" },
	geomancer  = { art = "kobold_geomancer", ring = 3, speed = 1, kill = 2, hit = 1, family = "kobold", name = "Kobold Geomancer",
		cast = { range = 3, turns = 2, damage = 2 } },
	rat        = { art = "tunnel_rat",       ring = 2, speed = 2, kill = 1, hit = 1, family = "kobold", name = "Tunnel Rat" },
	grizzle    = { art = "foreman_grizzlebeard", ring = 3, speed = 1, kill = 6, hit = 2, family = "kobold", boss = true,
		callsFamily = true, name = "Foreman Grizzlebeard" },
	-- Blackbrine Grotto
	smuggler   = { art = "smuggler",         ring = 2, speed = 1, kill = 2, hit = 1, family = "smuggler", name = "Blackbrine Smuggler" },
	bomber     = { art = "powder_bomber",    ring = 3, speed = 1, kill = 2, hit = 1, family = "smuggler", name = "Powder-Bomber",
		cast = { range = 3, turns = 2, damage = 2 } },
	crab       = { art = "shore_crab",       ring = 2, speed = 1, kill = 4, hit = 1, family = "crab", elite = true, name = "Shore Crab" },
	ilsa       = { art = "captain_ilsa_vane", ring = 3, speed = 1, kill = 6, hit = 2, family = "smuggler", boss = true,
		callsFamily = true, name = "Captain Ilsa Vane" },
	-- Ashveil Crypt
	skeleton   = { art = "skeleton",         ring = 2, speed = 1, kill = 2, hit = 1, family = "undead", name = "Skeleton" },
	ghoul      = { art = "ghoul",            ring = 2, speed = 2, kill = 2, hit = 1, family = "undead", name = "Ghoul" },
	banshee    = { art = "banshee",          ring = 3, speed = 1, kill = 2, hit = 1, family = "undead", name = "Banshee",
		cast = { range = 3, turns = 2, damage = 1, fear = true } },
	ambusher   = { art = "skeleton",         ring = 0, speed = 1, kill = 2, hit = 1, family = "undead", ambush = true,
		name = "Sarcophagus" },
	abbot      = { art = "hollow_abbot",     ring = 3, speed = 1, kill = 6, hit = 3, family = "undead", boss = true,
		name = "The Hollow Abbot" },
	-- Emberdeep Forge
	dwarf      = { art = "cinderguard_dwarf", ring = 2, speed = 1, kill = 2, hit = 1, family = "forge", name = "Cinderguard Dwarf" },
	firecaster = { art = "fire_caster",      ring = 3, speed = 1, kill = 2, hit = 1, family = "forge", name = "Fire-Caster",
		cast = { range = 3, turns = 2, damage = 2 } },
	hound      = { art = "magma_hound",      ring = 2, speed = 2, kill = 4, hit = 1, family = "forge", elite = true, name = "Magma Hound" },
	kolgrim    = { art = "thane_kolgrim",    ring = 3, speed = 1, kill = 6, hit = 2, family = "forge", boss = true, elite = true,
		statue = true, name = "Forgemaster Thane Kolgrim" },
}

local DIRS = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }
local ORDER = { "N", "E", "S", "W" }
R.DIRS, R.ORDER = DIRS, ORDER

-- ------------------------------------------------------------------ parsing
local CHAR = {
	["#"] = WALL, ["."] = FLOOR, [" "] = VOID, ["O"] = PILLAR, ["%"] = PROP,
	["~"] = WATER, ["^"] = LAVA, ["C"] = FLOOR, ["@"] = FLOOR,
}
-- the low props of each delve: a "%" on the map takes one of these, the same one every time
R.PROPS = {
	candlewick = { "barrel", "crate", "ore_cart" },
	blackbrine = { "barrel", "crate", "rope_bollard" },
	ashveil = { "bone_crate", "coffin", "urn" },
	emberdeep = { "anvil", "coal_cart", "iron_crate" },
}
local MOBCHAR = {
	d = "digger", g = "geomancer", r = "rat", G = "grizzle",
	s = "smuggler", p = "bomber", c = "crab", I = "ilsa",
	k = "skeleton", h = "ghoul", b = "banshee", a = "ambusher", A = "abbot",
	w = "dwarf", f = "firecaster", m = "hound", K = "kolgrim",
}

function R:Parse(room)
	local rows = room.map
	local H, Wd = #rows, 0
	for y = 1, H do Wd = max(Wd, #rows[y]) end
	if Wd > 15 or H > 11 then error(("room %s: %dx%d is larger than 15x11"):format(tostring(room.id), Wd, H)) end
	local b = { id = room.id, name = room.name, w = Wd, h = H, tile = {}, prop = {}, camp = {}, mobs = {},
		par = room.par, gold = room.gold, solution = room.solution, delve = room.delve, room = room }
	local campX, campY
	for y = 1, H do
		local row = rows[y]
		for x = 1, Wd do
			local ch = row:sub(x, x)
			if ch == "" then ch = " " end
			local i = (y - 1) * Wd + x
			local mk = MOBCHAR[ch]
			if mk then
				b.tile[i] = FLOOR
				b.mobs[#b.mobs + 1] = { kind = mk, x = x, y = y }
			else
				local t = CHAR[ch]
				if t == nil then error(("room %s: unknown map character %q at %d,%d"):format(tostring(room.id), ch, x, y)) end
				b.tile[i] = t
				if ch == "%" then
					local set = R.PROPS[room.delve or "candlewick"] or R.PROPS.candlewick
					b.prop[i] = set[(x * 3 + y) % #set + 1]
				end
				if ch == "C" then
					b.camp[i] = true
					if not campX or y < campY or (y == campY and x < campX) then campX, campY = x, y end
				elseif ch == "@" then
					b.sx, b.sy = x, y
				end
			end
		end
	end
	if not b.sx then error("room " .. tostring(room.id) .. ": no start (@)") end
	if not campX then error("room " .. tostring(room.id) .. ": no camp (C)") end
	b.campX, b.campY = campX, campY
	-- the healer stands at the rug's centre (a 2x2 rug: the shared corner of its four tiles)
	b.hx, b.hy = campX + 1, campY + 1
	-- per-mob overrides: rings = { [index] = radius }, links = { {i, j, ...}, ... }
	for idx, m in ipairs(b.mobs) do
		local k = R.KINDS[m.kind]
		m.ring = (room.rings and room.rings[idx]) or k.ring
		m.link = nil
	end
	-- patrols = { [index] = "EEEWWW" }: a sleeping (unaware) mob walks this loop, one step a turn
	if room.patrols then
		for idx, route in pairs(room.patrols) do
			if not b.mobs[idx] then error(("room %s: patrol names mob %d"):format(tostring(room.id), idx)) end
			if type(route) ~= "string" or route == "" or route:find("[^NESW]") then
				error(("room %s: patrol %d route %q"):format(tostring(room.id), idx, tostring(route)))
			end
			local dx, dy = 0, 0
			for c in route:gmatch(".") do dx, dy = dx + DIRS[c][1], dy + DIRS[c][2] end
			if dx ~= 0 or dy ~= 0 then error(("room %s: patrol %d does not come back to its start"):format(tostring(room.id), idx)) end
			b.mobs[idx].route = route
		end
	end
	if room.links then
		for g, list in ipairs(room.links) do
			for _, idx in ipairs(list) do
				if not b.mobs[idx] then error(("room %s: link %d names mob %d"):format(tostring(room.id), g, idx)) end
				b.mobs[idx].link = g
			end
		end
	end
	return b
end

local function Tile(b, x, y)
	if x < 1 or y < 1 or x > b.w or y > b.h then return VOID end
	return b.tile[(y - 1) * b.w + x]
end
R.Tile = Tile

local function TankCanEnter(t) return t == FLOOR or t == WATER or t == LAVA end
local function MobCanEnter(t) return t == FLOOR end
local function BlocksSight(t) return t == WALL or t == PILLAR or t == VOID end
R.TankCanEnter, R.MobCanEnter, R.BlocksSight = TankCanEnter, MobCanEnter, BlocksSight

-- ------------------------------------------------------------------ geometry
-- line of sight between two points (tile units, centres at x+0.5): sampled 8 times per tile, and a
-- sample landing exactly on a tile corner counts both diagonal neighbours, so sight never squeezes
-- between two walls that only touch at a corner.
local function SeesPoint(b, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local n = floor(max(abs(dx), abs(dy)) * 8) + 1
	for i = 1, n - 1 do
		local t = i / n
		local px, py = ax + dx * t, ay + dy * t
		local fx, fy = floor(px), floor(py)
		if BlocksSight(Tile(b, fx, fy)) then return false end
		if px == fx and py == fy then
			if BlocksSight(Tile(b, fx - 1, fy)) and BlocksSight(Tile(b, fx, fy - 1)) then return false end
			if BlocksSight(Tile(b, fx - 1, fy - 1)) and BlocksSight(Tile(b, fx, fy)) then return false end
		end
	end
	return true
end

-- tile (x, y) covers [x, x+1) in these units, so a tile's centre is x + 0.5
-- b.memo (set by the room tools, never in the game) caches sight and movement fields per board:
-- worth it for millions of turns, not worth the memory for a player's few hundred.
function R:Sees(b, ax, ay, bx, by)
	local memo = b.memo
	if memo then
		local k = ((ay * 64 + ax) * 64 + by) * 64 + bx
		local v = memo.los[k]
		if v == nil then
			v = SeesPoint(b, ax + 0.5, ay + 0.5, bx + 0.5, by + 0.5)
			memo.los[k] = v
		end
		return v
	end
	return SeesPoint(b, ax + 0.5, ay + 0.5, bx + 0.5, by + 0.5)
end

local function Within(dx, dy, r)
	-- a disc of radius r around the tile, generous enough that (r, 1) counts and (r, r) does not for r >= 2
	return dx * dx + dy * dy <= r * r + r
end
R.Within = Within

function R:InRing(b, m, x, y)
	return Within(x - m.x, y - m.y, m.ring) and self:Sees(b, m.x, m.y, x, y)
end

function R:HealerSees(b, s)
	local dx, dy = (s.tx + 0.5) - b.hx, (s.ty + 0.5) - b.hy
	if dx * dx + dy * dy > R.HEAL_RANGE * R.HEAL_RANGE then return false end
	local memo = b.memo
	if memo then
		local k = s.ty * 64 + s.tx
		local v = memo.heal[k]
		if v == nil then
			v = SeesPoint(b, b.hx, b.hy, s.tx + 0.5, s.ty + 0.5)
			memo.heal[k] = v
		end
		return v
	end
	return SeesPoint(b, b.hx, b.hy, s.tx + 0.5, s.ty + 0.5)
end

-- inside the party ring: where Kesk and Wyn can reach (drawn around the rug on the board)
function R:InParty(b, x, y)
	local dx, dy = x + 0.5 - b.hx, y + 0.5 - b.hy
	return dx * dx + dy * dy <= R.PARTY_RADIUS * R.PARTY_RADIUS
end

function R:OnCamp(b, x, y)
	return b.camp[(y - 1) * b.w + x] == true
end

-- ------------------------------------------------------------------ state
function R:New(b)
	local s = { tx = b.sx, ty = b.sy, pips = R.MAX_PIPS, steps = 0, over = nil, mobs = {}, waits = 0, dmgTaken = 0 }
	for i, m in ipairs(b.mobs) do
		s.mobs[i] = { x = m.x, y = m.y, awake = false, alive = true, cast = 0, dmg = 0, pi = 0 }
	end
	return s
end

function R:Copy(s)
	local c = { tx = s.tx, ty = s.ty, pips = s.pips, steps = s.steps, over = s.over, waits = s.waits,
		dmgTaken = s.dmgTaken, mobs = {} }
	for i, m in ipairs(s.mobs) do
		c.mobs[i] = { x = m.x, y = m.y, awake = m.awake, alive = m.alive, cast = m.cast, dmg = m.dmg, pi = m.pi }
	end
	return c
end

function R:Restore(s, c)
	s.tx, s.ty, s.pips, s.steps, s.over, s.waits, s.dmgTaken = c.tx, c.ty, c.pips, c.steps, c.over, c.waits, c.dmgTaken
	for i, m in ipairs(c.mobs) do
		local d = s.mobs[i]
		d.x, d.y, d.awake, d.alive, d.cast, d.dmg, d.pi = m.x, m.y, m.awake, m.alive, m.cast, m.dmg, m.pi
	end
end

local keyBuf = {}
function R:Key(s)
	local n = 0
	n = n + 1; keyBuf[n] = s.tx
	n = n + 1; keyBuf[n] = s.ty
	n = n + 1; keyBuf[n] = s.pips
	for _, m in ipairs(s.mobs) do
		if not m.alive then
			n = n + 1; keyBuf[n] = "x"
		elseif not m.awake then
			n = n + 1; keyBuf[n] = "z" .. m.pi      -- a patrol's place follows from its route step
		else
			n = n + 1; keyBuf[n] = m.x .. ":" .. m.y .. ":" .. m.cast .. ":" .. m.dmg
		end
	end
	for i = n + 1, #keyBuf do keyBuf[i] = nil end
	return concat(keyBuf, ",")
end

-- ------------------------------------------------------------------ movement field
-- distance (in mob steps) from every tile to the tank, through tiles mobs can walk; other mobs are
-- ignored here (they block occupancy, not the field), so a pack queues up instead of wandering off.
local dist, queue = {}, {}
local function Field(b, s)
	local Wd, Ht = b.w, b.h
	local memo = b.memo
	if memo then
		local ti = (s.ty - 1) * Wd + s.tx
		local f = memo.field[ti]
		if f then dist = f return end
		f = {}
		memo.field[ti] = f
		dist = f
	end
	local N = Wd * Ht
	for i = 1, N do dist[i] = nil end
	local head, tail = 1, 1
	local ti = (s.ty - 1) * Wd + s.tx
	dist[ti] = 0
	queue[1] = ti
	while head <= tail do
		local i = queue[head]
		head = head + 1
		local x, y = (i - 1) % Wd + 1, floor((i - 1) / Wd) + 1
		local d = dist[i] + 1
		for k = 1, 4 do
			local o = DIRS[ORDER[k]]
			local nx, ny = x + o[1], y + o[2]
			if nx >= 1 and ny >= 1 and nx <= Wd and ny <= Ht then
				local j = (ny - 1) * Wd + nx
				if dist[j] == nil and MobCanEnter(b.tile[j]) then
					dist[j] = d
					tail = tail + 1
					queue[tail] = j
				end
			end
		end
	end
end

local function Occupied(s, x, y, self)
	for _, m in ipairs(s.mobs) do
		if m ~= self and m.alive and m.x == x and m.y == y then return true end
	end
	return false
end
R.Occupied = Occupied

local function Adjacent(ax, ay, bx, by) return abs(ax - bx) + abs(ay - by) == 1 end
R.Adjacent = Adjacent

local function Emit(ev, kind, a, b2, c)
	if ev then ev[#ev + 1] = { kind, a, b2, c } end
end

-- one step toward the tank: the neighbour that brings the mob closest (N, E, S, W on ties), never
-- onto another mob or the tank. Returns true if it moved.
local function StepToward(b, s, m)
	local Wd = b.w
	local here = dist[(m.y - 1) * Wd + m.x]
	local bestD, bx, by
	for k = 1, 4 do
		local o = DIRS[ORDER[k]]
		local nx, ny = m.x + o[1], m.y + o[2]
		if nx >= 1 and ny >= 1 and nx <= Wd and ny <= b.h then
			local d = dist[(ny - 1) * Wd + nx]
			if d and (here == nil or d < here) and (bestD == nil or d < bestD)
				and not (nx == s.tx and ny == s.ty) and not Occupied(s, nx, ny, m) then
				bestD, bx, by = d, nx, ny
			end
		end
	end
	if bx then
		m.x, m.y = bx, by
		return true
	end
	return false
end

local function Wake(b, s, i, ev, cause)
	local m = s.mobs[i]
	if m.awake or not m.alive then return 0 end
	m.awake = true
	m.fresh = true
	Emit(ev, "wake", i, cause)
	return 1
end

-- every sleeper that should wake does (repeat until nothing new wakes: a pack or a boss can wake mobs
-- whose own rings miss). A sleeper notices the tank inside its ring where it can see it; an ambusher
-- (a closed sarcophagus) only when the tank stands right next to it.
local function WakeAll(self, b, s, ev)
	local mobs = s.mobs
	local changed = true
	while changed do
		changed = false
		for i = 1, #mobs do
			local m = mobs[i]
			if m.alive and not m.awake then
				local d = b.mobs[i]
				local k = R.KINDS[d.kind]
				local seen
				if k.ambush then
					seen = Adjacent(m.x, m.y, s.tx, s.ty)
				else
					seen = Within(s.tx - m.x, s.ty - m.y, d.ring) and self:Sees(b, m.x, m.y, s.tx, s.ty)
				end
				if seen then
					Wake(b, s, i, ev, k.ambush and "ambush" or "sight")
					changed = true
				end
			end
		end
		for i = 1, #mobs do
			local m, d = mobs[i], b.mobs[i]
			if m.alive and m.awake and m.fresh then
				if d.link then
					local n = 0
					for j = 1, #mobs do
						if b.mobs[j].link == d.link then n = n + Wake(b, s, j, ev, "link") end
					end
					if n > 0 then Emit(ev, "pack", d.link) changed = true end
				end
				local k = R.KINDS[d.kind]
				if k.callsFamily and not m.called then
					m.called = true    -- once per turn (cleared at the start of each turn)
					Emit(ev, "boss", i)
					for j = 1, #mobs do
						if R.KINDS[b.mobs[j].kind].family == k.family then
							if Wake(b, s, j, ev, "boss") > 0 then changed = true end
						end
					end
				end
			end
		end
	end
end

-- a sleeping patrol takes the next step of its loop (it waits while something stands in the way)
local function Patrol(b, s, i, ev)
	local m, d = s.mobs[i], b.mobs[i]
	local route = d.route
	local a = route:sub(m.pi + 1, m.pi + 1)
	local o = DIRS[a]
	local nx, ny = m.x + o[1], m.y + o[2]
	if MobCanEnter(Tile(b, nx, ny)) and not (nx == s.tx and ny == s.ty) and not Occupied(s, nx, ny, m) then
		m.x, m.y = nx, ny
		m.pi = (m.pi + 1) % #route
		Emit(ev, "patrol", i, nx, ny)
	end
end

-- a landed fear: the tank stumbles one tile straight away from the caster, if that tile is free
local function Fear(b, s, m, ev)
	local dx, dy = s.tx - m.x, s.ty - m.y
	local ox, oy = 0, 0
	if abs(dx) >= abs(dy) then ox = dx > 0 and 1 or (dx < 0 and -1 or 0) else oy = dy > 0 and 1 or -1 end
	if ox == 0 and oy == 0 then return false end
	local nx, ny = s.tx + ox, s.ty + oy
	if TankCanEnter(Tile(b, nx, ny)) and not Occupied(s, nx, ny) then
		s.tx, s.ty = nx, ny
		Emit(ev, "fear", nx, ny)
		return true
	end
	return false
end

--[[ R:Act - one turn. Mutates s. ev collects { kind, a, b, c } records in order:
	"move" dir | "bump" dir | "wait" | "wake" i cause | "pack" link | "boss" i | "dps" i progress |
	"kill" i | "hit" i dmg | "caststart" i | "cast" i dmg | "fear" x y | "fizzle" i | "statue" i |
	"mstep" i x y | "patrol" i x y | "burn" | "heal" | "nosight" | "wipe" | "clear" ]]
function R:Act(b, s, action, ev)
	if s.over then return false end
	local nx, ny = s.tx, s.ty
	if action ~= "." then
		local o = DIRS[action]
		if not o then return false end
		nx, ny = s.tx + o[1], s.ty + o[2]
		if not TankCanEnter(Tile(b, nx, ny)) or Occupied(s, nx, ny) then
			Emit(ev, "bump", action)
			return false
		end
	end
	-- 1. the tank
	if action == "." then
		s.waits = s.waits + 1
		Emit(ev, "wait")
	else
		s.tx, s.ty = nx, ny
		Emit(ev, "move", action)
	end
	s.steps = s.steps + 1
	local mobs = s.mobs
	for i = 1, #mobs do mobs[i].fresh = nil mobs[i].called = nil end

	-- 2. waking
	WakeAll(self, b, s, ev)

	-- 3. the party's DPS: while the tank holds the pull inside the party ring, they hit a mob in the ring
	if self:InParty(b, s.tx, s.ty) then
		local best, bi
		for i = 1, #mobs do
			local m = mobs[i]
			if m.alive and m.awake and self:InParty(b, m.x, m.y) then
				if best == nil or m.dmg > best.dmg then best, bi = m, i end
			end
		end
		if best then
			best.dmg = best.dmg + 1
			local k = R.KINDS[b.mobs[bi].kind]
			Emit(ev, "dps", bi, best.dmg)
			if best.dmg >= k.kill then
				best.alive = false
				best.cast = 0
				Emit(ev, "kill", bi)
			end
		end
	end

	-- 4. the mobs: awake ones fight, sleeping patrols walk their loops
	Field(b, s)
	for i = 1, #mobs do
		local m = mobs[i]
		if m.alive and m.awake and not m.fresh then
			local k = R.KINDS[b.mobs[i].kind]
			local c = k.cast
			if c and m.cast > 0 then
				m.cast = m.cast - 1
				if m.cast == 0 then
					if Within(s.tx - m.x, s.ty - m.y, c.range) and self:Sees(b, m.x, m.y, s.tx, s.ty) then
						s.pips = s.pips - c.damage
						s.dmgTaken = s.dmgTaken + c.damage
						Emit(ev, "cast", i, c.damage)
						if c.fear and Fear(b, s, m, ev) then Field(b, s) end
					else
						Emit(ev, "fizzle", i)
					end
				end
			elseif Adjacent(m.x, m.y, s.tx, s.ty) then
				s.pips = s.pips - k.hit
				s.dmgTaken = s.dmgTaken + k.hit
				Emit(ev, "hit", i, k.hit)
			elseif c and Within(s.tx - m.x, s.ty - m.y, c.range) and self:Sees(b, m.x, m.y, s.tx, s.ty) then
				m.cast = c.turns
				Emit(ev, "caststart", i)
			elseif k.statue and not self:Sees(b, m.x, m.y, s.tx, s.ty) then
				Emit(ev, "statue", i)       -- out of his sight he stands like stone
			else
				for _ = 1, k.speed do
					if Adjacent(m.x, m.y, s.tx, s.ty) or not StepToward(b, s, m) then break end
					Emit(ev, "mstep", i, m.x, m.y)
				end
			end
		elseif m.alive and not m.awake and b.mobs[i].route then
			Patrol(b, s, i, ev)
		end
	end
	-- a patrol that walked into view of the tank notices it now (it acts from next turn)
	WakeAll(self, b, s, ev)

	-- lava burns whoever ends a turn on it (mobs never step there)
	if Tile(b, s.tx, s.ty) == LAVA then
		s.pips = s.pips - 1
		s.dmgTaken = s.dmgTaken + 1
		Emit(ev, "burn")
	end

	-- 5. wipe, 6. heal, 7. clear
	if s.pips <= 0 then
		s.pips = 0
		s.over = "wipe"
		Emit(ev, "wipe")
		return true
	end
	if s.pips < R.MAX_PIPS then
		if self:HealerSees(b, s) then
			s.pips = s.pips + 1
			Emit(ev, "heal")
		else
			Emit(ev, "nosight")
		end
	end
	local left = 0
	for i = 1, #mobs do if mobs[i].alive then left = left + 1 end end
	if left == 0 then
		s.over = "clear"
		Emit(ev, "clear")
	end
	return true
end

-- the medal a finished run earns: 3 gold, 2 silver, 1 bronze (0 = not cleared)
function R:Medal(b, steps)
	if not steps then return 0 end
	if b.gold and steps <= b.gold then return 3 end
	if b.par and steps <= b.par then return 2 end
	return 1
end

-- replay a move string ("NNE.S...") from the start; returns the final state and how many moves ran
function R:Replay(b, moves)
	local s = self:New(b)
	local n = 0
	for i = 1, #moves do
		local a = moves:sub(i, i)
		if s.over then break end
		if not self:Act(b, s, a) then return s, n, "blocked at move " .. i end
		n = n + 1
	end
	return s, n
end

return R
