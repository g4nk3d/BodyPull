--[[ Body Pull - Game/Awards.lua
	Achievements and shield skins. Nothing here is counted turn by turn: when a room is cleared, its
	winning moves are replayed once (the rules are deterministic) and the replay's events decide what
	was earned, so undo and restart can never fake or lose an award.

	  Aw.LIST                     the 13 achievements, in display order
	  Aw:Has(id)                  earned by this character?
	  Aw:OnClear(b, moves, daily) a clear: returns the list of achievements newly earned (and records them)
	  Aw.SKINS                    the 8 shield skins, in display order
	  Aw:SkinOpen(id)             earned?  Aw:SkinNeed(id) what earns it
	  Aw:Skin() / Aw:SetSkin(id)  the shield this character carries ]]

local _, ns = ...
local P = ns.P
local Aw = P:Module("Awards")
local R = ns.Rules

local function Pr() return P.Progress end

-- id, name, what earns it, badge sprite
Aw.LIST = {
	{ id = "first_pull",  name = "First Pull",   about = "Clear your first room.",                                        badge = "achievement_first_pull" },
	{ id = "clean_pull",  name = "Clean Pull",   about = "Clear a room without taking a single hit.",                     badge = "achievement_clean_pull" },
	{ id = "corner_pull", name = "Corner Pull",  about = "Break a caster's sight so its cast fizzles, and clear the room.", badge = "achievement_corner_pull" },
	{ id = "patience",    name = "Patience",     about = "Wait five turns in a row and still clear the room.",           badge = "achievement_patience" },
	{ id = "candlewick",  name = "Candlewick Mine",   about = "Clear all ten rooms of Candlewick Mine.",                badge = "achievement_candlewick_clear", delve = "candlewick" },
	{ id = "blackbrine",  name = "Blackbrine Grotto", about = "Clear all ten rooms of Blackbrine Grotto.",              badge = "achievement_blackbrine_clear", delve = "blackbrine" },
	{ id = "ashveil",     name = "Ashveil Crypt",     about = "Clear all ten rooms of Ashveil Crypt.",                  badge = "achievement_ashveil_clear", delve = "ashveil" },
	{ id = "emberdeep",   name = "Emberdeep Forge",   about = "Clear all ten rooms of Emberdeep Forge.",                badge = "achievement_emberdeep_clear", delve = "emberdeep" },
	{ id = "grizzlebeard", name = "Foreman Down",  about = "Defeat Foreman Grizzlebeard.",                                badge = "achievement_grizzlebeard", boss = "grizzle" },
	{ id = "ilsa",        name = "Anchor Dropped", about = "Defeat Captain Ilsa Vane.",                                  badge = "achievement_ilsa_vane", boss = "ilsa" },
	{ id = "abbot",       name = "Last Rites",     about = "Defeat the Hollow Abbot.",                                   badge = "achievement_hollow_abbot", boss = "abbot" },
	{ id = "kolgrim",     name = "Cold Iron",      about = "Defeat Thane Kolgrim.",                                      badge = "achievement_kolgrim", boss = "kolgrim" },
	{ id = "daily_regular", name = "Daily Regular", about = "Clear the daily room on seven different days.",             badge = "achievement_daily_regular" },
}
local byId = {}
for _, a in ipairs(Aw.LIST) do byId[a.id] = a end
function Aw:Get(id) return byId[id] end

-- the shield skins: what each one shows and what earns it
Aw.SKINS = {
	{ id = "iron",            name = "Iron",             need = "Every tank starts with it." },
	{ id = "oak",             name = "Oak",              need = "Clear Candlewick Mine.",           ach = "candlewick" },
	{ id = "smuggler_anchor", name = "Smuggler's Anchor", need = "Clear Blackbrine Grotto.",        ach = "blackbrine" },
	{ id = "crypt_bone",      name = "Crypt Bone",       need = "Clear Ashveil Crypt.",             ach = "ashveil" },
	{ id = "forge_ember",     name = "Forge Ember",      need = "Clear Emberdeep Forge.",           ach = "emberdeep" },
	{ id = "brass",           name = "Brass",            need = "Earn silver or better in 10 rooms.", silver = 10 },
	{ id = "silver",          name = "Silver",           need = "Earn gold in 25 rooms.",           gold = 25 },
	{ id = "gold",            name = "Gold",             need = "Earn gold in all 40 rooms.",       gold = 40 },
}
local skinById = {}
for _, k in ipairs(Aw.SKINS) do skinById[k.id] = k end

local function Char() return P.char end
local function Earned()
	local c = Char()
	if not c then return {} end
	if type(c.ach) ~= "table" then c.ach = {} end
	return c.ach
end

function Aw:Has(id) return Earned()[id] ~= nil end
function Aw:Count()
	local n = 0
	for _, a in ipairs(self.LIST) do if self:Has(a.id) then n = n + 1 end end
	return n, #self.LIST
end

-- medals across the whole campaign: rooms at silver or better, rooms at gold
function Aw:MedalCounts()
	local silver, gold = 0, 0
	for _, d in ipairs(Pr():Delves()) do
		for _, room in ipairs(Pr():Rooms(d.id)) do
			local r = Pr():Record(room.id)
			local m = r and r.medal or 0
			if m >= 2 then silver = silver + 1 end
			if m >= 3 then gold = gold + 1 end
		end
	end
	return silver, gold
end

function Aw:SkinOpen(id)
	local k = skinById[id]
	if not k then return false end
	if k.ach then return self:Has(k.ach) end
	if k.silver or k.gold then
		local silver, gold = self:MedalCounts()
		return silver >= (k.silver or 0) and gold >= (k.gold or 0)
	end
	return true
end
function Aw:SkinNeed(id) local k = skinById[id] return k and k.need or "" end
function Aw:SkinName(id) local k = skinById[id] return k and k.name or "Iron" end

function Aw:Skin()
	local c = Char()
	local id = c and c.skin
	if type(id) ~= "string" or not skinById[id] or not self:SkinOpen(id) then return "iron" end
	return id
end

function Aw:SetSkin(id)
	local c = Char()
	if not c or P.readOnly or not skinById[id] or not self:SkinOpen(id) then return false end
	c.skin = id
	P:Fire("SKIN_CHANGED", id)
	return true
end

-- skins that are open now but were not before (for the results screen)
local function OpenSkins()
	local t = {}
	for _, k in ipairs(Aw.SKINS) do if Aw:SkinOpen(k.id) then t[k.id] = true end end
	return t
end

local function Give(id, list)
	local e = Earned()
	if e[id] or P.readOnly then return end
	e[id] = (GetServerTime and GetServerTime()) or (time and time()) or 0
	list[#list + 1] = byId[id]
end

-- A clear: the winning moves are replayed a few per frame (a whole replay in one frame was a 10 ms hitch),
-- then done(newAchievements, newSkins) is called. Aw:OnClear(b, moves, daily) does the same at once
-- (tests and tools).
local MOVES_PER_FRAME = 6
local evBuf = {}
local function Begin(b, moves, daily)
	return { b = b, moves = moves, daily = daily, s = R:New(b), i = 0, hurt = false, fizzled = false, killed = {},
		before = OpenSkins() }
end

-- advance a replay by up to n moves; true when it has finished
local function Advance(j, n)
	local b, s = j.b, j.s
	for _ = 1, n do
		if s.over or j.i >= #j.moves then return true end
		j.i = j.i + 1
		wipe(evBuf)
		if not R:Act(b, s, j.moves:sub(j.i, j.i), evBuf) then j.blocked = true return true end
		for _, e in ipairs(evBuf) do
			local k = e[1]
			if k == "hit" or k == "cast" or k == "burn" then j.hurt = true
			elseif k == "fizzle" then j.fizzled = true
			elseif k == "kill" then j.killed[b.mobs[e[2]].kind] = true end
		end
	end
	return j.s.over ~= nil or j.i >= #j.moves
end

local function Award(j)
	local new, skins = {}, {}
	if j.blocked or j.s.over ~= "clear" then return new, skins end
	Give("first_pull", new)
	if not j.hurt then Give("clean_pull", new) end
	if j.fizzled then Give("corner_pull", new) end
	if j.moves:find(".....", 1, true) then Give("patience", new) end
	for _, a in ipairs(Aw.LIST) do
		if a.boss and j.killed[a.boss] then Give(a.id, new) end
		if a.delve then
			local cleared, total = Pr():Count(a.delve)
			if total > 0 and cleared == total then Give(a.id, new) end
		end
	end
	if j.daily and P.Daily and P.Daily:DaysCleared() >= 7 then Give("daily_regular", new) end
	for _, k in ipairs(Aw.SKINS) do
		if not j.before[k.id] and Aw:SkinOpen(k.id) then skins[#skins + 1] = k end
	end
	if #new > 0 then P:Fire("ACHIEVEMENTS", new) end
	return new, skins
end

function Aw:OnClear(b, moves, daily)
	if not Char() or type(moves) ~= "string" then return {}, {} end
	local j = Begin(b, moves, daily)
	Advance(j, #moves + 1)
	return Award(j)
end

local queue = {}
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
	local j = queue[1]
	if not j then self:Hide() return end
	if Advance(j, MOVES_PER_FRAME) then
		table.remove(queue, 1)
		local new, skins = Award(j)
		if j.done then P:Safe("awards", j.done, new, skins) end
	end
end)

function Aw:OnClearAsync(b, moves, daily, done)
	if not Char() or type(moves) ~= "string" then if done then done({}, {}) end return end
	local j = Begin(b, moves, daily)
	j.done = done
	queue[#queue + 1] = j
	runner:Show()
end
function Aw:Busy() return #queue > 0 end
