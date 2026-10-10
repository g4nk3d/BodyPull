--[[ Body Pull - Game/Progress.lua
	The campaign's rooms and this character's records (best steps, medal, the winning moves).

	  Pr:Rooms(delve)          the rooms of a delve, in order
	  Pr:Room(id)              a room's definition; Pr:Board(id) its parsed board (only the latest one is kept)
	  Pr:Record(id)            this character's record { best, medal, moves } or nil
	  Pr:Unlocked(id)          the first room is open; each later one opens when the one before is cleared
	  Pr:Finish(id, s, moves)  a clear: keeps the best; returns medal, isNewBest, previousBest
	  Pr:Next(id)              the room after this one in its delve (or nil)
	  Pr:Delves()              the delves in campaign order, with names ]]

local _, ns = ...
local P = ns.P
local Pr = P:Module("Progress")
local R = ns.Rules

Pr.DELVES = {
	{ id = "candlewick", name = "Candlewick Mine",
		about = "Kobold diggers, geomancers and tunnel rats. Learn rings, chains and sight lines." },
	{ id = "blackbrine", name = "Blackbrine Grotto",
		about = "A flooded smugglers' cave. You can wade, they can't, and patrols walk their beats." },
	{ id = "ashveil", name = "Ashveil Crypt",
		about = "Bone-white halls. Ghouls run, coffins open when you pass, banshees wail you backwards." },
	{ id = "emberdeep", name = "Emberdeep Forge",
		about = "Black iron and lava. Hounds, fire-casters, and a Forgemaster who moves only when watched." },
}
local delveIndex = {}
for i, d in ipairs(Pr.DELVES) do delveIndex[d.id] = i end
function Pr:Delve(id) return self.DELVES[delveIndex[id] or 1] end

local byId, byDelve = {}, {}
local lastId, lastBoard          -- only the room being played stays parsed
for _, room in ipairs(ns.Rooms or {}) do
	byId[room.id] = room
	byDelve[room.delve] = byDelve[room.delve] or {}
	local list = byDelve[room.delve]
	list[#list + 1] = room
	room.index = #list
end

function Pr:Delves() return self.DELVES end
function Pr:Rooms(delve) return byDelve[delve] or {} end
function Pr:Room(id) return byId[id] end

function Pr:Board(id)
	if id == lastId and lastBoard then return lastBoard end
	local room = byId[id]
	if not room then return nil end
	lastId, lastBoard = id, R:Parse(room)
	return lastBoard
end

function Pr:Record(id)
	local c = P.char
	return c and c.rooms[id]
end

function Pr:Unlocked(id)
	local room = byId[id]
	if not room then return false end
	if P.testOpen then return true end      -- /bodypull testrooms: every room open this session only
	if room.index == 1 then
		-- a delve opens when the last room of the delve before it is cleared
		local di = delveIndex[room.delve] or 1
		if di == 1 then return true end
		local prevList = byDelve[self.DELVES[di - 1].id]
		local last = prevList and prevList[#prevList]
		local r = last and self:Record(last.id)
		return r ~= nil and (r.medal or 0) > 0
	end
	local prev = byDelve[room.delve][room.index - 1]
	local r = self:Record(prev.id)
	return r ~= nil and (r.medal or 0) > 0
end

function Pr:Next(id)
	local room = byId[id]
	if not room then return nil end
	local nxt = byDelve[room.delve][room.index + 1]
	if not nxt then
		-- the first room of the next delve
		local di = delveIndex[room.delve] or 1
		local d = self.DELVES[di + 1]
		nxt = d and byDelve[d.id] and byDelve[d.id][1]
	end
	return nxt and nxt.id
end

function Pr:DelveOpen(delve)
	local list = byDelve[delve]
	return list ~= nil and list[1] ~= nil and self:Unlocked(list[1].id)
end

function Pr:Finish(id, s, moves)
	local b = self:Board(id)
	local medal = R:Medal(b, s.steps)
	local c = P.char
	if not c or P.readOnly then return medal, false, nil end
	local r = c.rooms[id]
	if not r then
		r = { medal = 0 }
		c.rooms[id] = r
	end
	local prev = r.best
	local newBest = prev == nil or s.steps < prev
	if newBest then
		r.best = s.steps
		r.moves = moves
	end
	if medal > (r.medal or 0) then r.medal = medal end
	r.clears = (tonumber(r.clears) or 0) + 1
	P:Fire("PROGRESS", id)
	return medal, newBest, prev
end

-- medals and clears across a delve (level select, NetherSuite status)
function Pr:Count(delve)
	local cleared, medals, total = 0, 0, 0
	for _, room in ipairs(self:Rooms(delve)) do
		total = total + 1
		local r = self:Record(room.id)
		if r and (r.medal or 0) > 0 then
			cleared = cleared + 1
			medals = medals + r.medal
		end
	end
	return cleared, total, medals
end
