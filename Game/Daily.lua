--[[ Body Pull - Game/Daily.lua
	The daily room: one of the forty campaign rooms, the same for every player in the world on the same
	date (the date is UTC, from the realm's clock). It can be played whether or not that room is open in
	your campaign, and its records are kept apart: a daily clear never changes campaign progress.

	  Dy:Today()              "2026-10-10", the day number
	  Dy:RoomId([day])        the room of that day
	  Dy:Record([date])       this character's record for that date { best, medal, moves } or nil
	  Dy:Finish(date, s, moves, b)  a daily clear: keeps the best; returns medal, isNewBest, previousBest
	  Dy:DaysCleared()        how many different days this character has cleared the daily room
	  Dy.BOARD_PREFIX         leaderboard id of a day's board: "d" .. date ]]

local _, ns = ...
local P = ns.P
local Dy = P:Module("Daily")
local R = ns.Rules

Dy.BOARD_PREFIX = "d"
local KEEP_DAYS = 60

local function Now()
	if GetServerTime then
		local ok, t = pcall(GetServerTime)
		if ok and type(t) == "number" and t > 0 then return t end
	end
	return time and time() or 0
end

-- the UTC calendar date of a day number (days since 1970-01-01), worked out by hand so it never depends
-- on the player's time zone (Howard Hinnant's civil-from-days)
local function DateOf(day)
	local z = day + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return ("%04d-%02d-%02d"):format(y, m, d)
end
Dy.DateOf = DateOf

function Dy:Day() return math.floor(Now() / 86400) end
function Dy:Today()
	local day = self:Day()
	return DateOf(day), day
end

-- every room in campaign order
local all
local function AllRooms()
	if all then return all end
	all = {}
	for _, d in ipairs(P.Progress:Delves()) do
		for _, room in ipairs(P.Progress:Rooms(d.id)) do all[#all + 1] = room.id end
	end
	return all
end

-- the day's room: a fixed shuffle of the 40 rooms, walked one per day, so every room comes round once
-- every forty days and two days in a row never share a delve
local ORDER
local function Order()
	if ORDER then return ORDER end
	local list = AllRooms()
	local n = #list
	ORDER = {}
	-- 17 is coprime with 40: stepping by it visits every room; rooms of one delve are 10 apart in the
	-- list, and a step of 17 always lands in another delve's block
	local i = 0
	for k = 1, n do
		ORDER[k] = list[i + 1]
		i = (i + 17) % n
	end
	return ORDER
end

function Dy:RoomId(day)
	local o = Order()
	if #o == 0 then return nil end
	day = day or self:Day()
	return o[(day % #o) + 1]
end

local function Days()
	local c = P.char
	if not c then return {} end
	if type(c.daily) ~= "table" then c.daily = {} end
	return c.daily
end

function Dy:Record(date) return Days()[date or self:Today()] end

function Dy:DaysCleared()
	local c = P.char
	return c and tonumber(c.dailyDays) or 0
end

function Dy:Finish(date, s, moves, b)
	local medal = R:Medal(b, s.steps)
	local c = P.char
	if not c or P.readOnly then return medal, false, nil end
	local days = Days()
	local r = days[date]
	if not r then
		r = { medal = 0 }
		days[date] = r
		c.dailyDays = (tonumber(c.dailyDays) or 0) + 1
	end
	local prev = r.best
	local newBest = prev == nil or s.steps < prev
	if newBest then
		r.best = s.steps
		r.moves = moves
		r.room = b.id
	end
	if medal > (r.medal or 0) then r.medal = medal end
	-- old days are let go (the count of days cleared stays)
	local today = self:Day()
	for d in pairs(days) do
		local y, m, dd = tostring(d):match("^(%d+)-(%d+)-(%d+)$")
		if not y then days[d] = nil
		else
			-- rough age in days is enough here
			local age = today - ((tonumber(y) - 1970) * 365.25 + (tonumber(m) - 1) * 30.44 + tonumber(dd))
			if age > KEEP_DAYS + 5 then days[d] = nil end
		end
	end
	P:Fire("DAILY", date)
	return medal, newBest, prev
end
