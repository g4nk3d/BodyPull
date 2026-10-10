--[[ Body Pull - Comm/Leaderboard.lua
	The SHARED LEADERBOARD: the fewest steps anyone has cleared each room in (and each day's daily room),
	passed between Body Pull players and checked by re-playing the moves before an entry counts.

	How scores travel (chat channels keep no history, so players tell each other; the same way as Piggle):
	  * the family's ONE hidden games channel, "PiggleScores" (Piggle made it first; every Nether minigame
	    shares it, each with its own message prefix, so a player only ever gives up one channel slot),
	    plus the guild. The channel is removed from every chat window, its notices are hidden, and it is
	    kept behind the game's own channels (NetherChannels.lua);
	  * on login a player asks ("Q"); everyone who hears it answers after a random 2-9 s with the best
	    entries they know, skipping anything someone else has just sent (no flood with many players online);
	  * a new best that makes a board's top ten is sent at once;
	  * every entry carries its moves. It is stored only after this client replays them on the same room
	    and gets a clear in exactly the claimed steps. Replays run a few moves per frame (never a spike).
	  Messages go out one every 0.35 s, never in combat. The setting "Share scores" turns all of it off.

	SEALED RECORDS: on logout this character's records are sealed (a digest of them, the character and a
	salt). If the saved file was edited outside the game the seal fails and every record is replayed again:
	only records whose own moves really clear the room in that many steps are kept.

	  LB:Board(id) -> top ten { who, s, t, m, g }  (id: a room id, or "d" .. date for a daily room)
	  LB:Record(id, steps, moves)                   a clear by this player
	  LB:Enabled() / LB:SetEnabled(on)
	  LB:Pending()                                  replays waiting to be checked ]]

local _, ns = ...
local P = ns.P
local LB = P:Module("Leaderboard")
local R = ns.Rules

local PREFIX, CHANNEL, SEP = "BodyPull1", "PiggleScores", "~"      -- the shared channel; our own prefix
local TOP, CHUNK, MAX_MOVES = 10, 200, 600
local MOVES_PER_FRAME = 8
local SALT = "bodypull-seal-1"
LB.CHANNEL, LB.PREFIX = CHANNEL, PREFIX


local function DB()
	local d = P.db and P.db.board
	if type(d) ~= "table" then
		d = {}
		if P.db then P.db.board = d end
	end
	return d
end

function LB:Enabled() return P:Setting("shareScores") ~= false end
function LB:Board(id) return DB()[id] or {} end

-- ------------------------------------------------------------------ which room a board is
local function DayOfDate(date)
	local y, m, d = tostring(date):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	-- days from civil (the inverse of Daily.DateOf)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = m > 2 and m - 3 or m + 9
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
LB.DayOfDate = DayOfDate

-- the room a board id is played on, or nil if the id is not a real board (a daily board only for
-- yesterday, today or tomorrow: realms' clocks differ a little)
function LB:RoomOf(id)
	if type(id) ~= "string" then return nil end
	local date = id:match("^" .. P.Daily.BOARD_PREFIX .. "(%d%d%d%d%-%d%d%-%d%d)$")
	if date then
		local day = DayOfDate(date)
		if not day or math.abs(day - P.Daily:Day()) > 1 then return nil end
		if P.Daily.DateOf(day) ~= date then return nil end
		return P.Daily:RoomId(day)
	end
	return P.Progress:Room(id) and id or nil
end

-- ------------------------------------------------------------------ the shared tables
-- one entry per player per board (their best), fewest steps first, at most ten
local function Qualifies(list, e)
	for _, o in ipairs(list) do
		if o.who == e.who and o.s <= e.s then return false end
	end
	return #list < TOP or e.s < list[#list].s
end

local function Insert(id, e)
	local d = DB()
	local list = d[id] or {}
	d[id] = list
	if not Qualifies(list, e) then return false end
	for i = #list, 1, -1 do if list[i].who == e.who then table.remove(list, i) end end
	local at = #list + 1
	while at > 1 and (list[at - 1].s > e.s or (list[at - 1].s == e.s and (list[at - 1].t or 0) > (e.t or 0))) do at = at - 1 end
	table.insert(list, at, { who = e.who, s = e.s, t = e.t, m = e.m, g = e.g or nil })
	while #list > TOP do table.remove(list) end
	P:Fire("LEADERBOARD_CHANGED", id)
	return true
end
LB.Insert = Insert

-- daily boards older than a week are let go
local function Prune()
	local d, today = DB(), P.Daily:Day()
	for id in pairs(d) do
		local date = id:match("^" .. P.Daily.BOARD_PREFIX .. "(%d%d%d%d%-%d%d%-%d%d)$")
		if date then
			local day = DayOfDate(date)
			if not day or today - day > 7 then d[id] = nil end
		elseif not P.Progress:Room(id) then
			d[id] = nil
		end
	end
end

-- ------------------------------------------------------------------ replay checks (a few moves a frame)
local jobs, job = {}, nil
local checker = CreateFrame("Frame")
checker:Hide()

local function Finish(ok)
	local j = job
	job = nil
	if j and j.done then P:Safe("replay check", j.done, ok) end
end

checker:SetScript("OnUpdate", function(self)
	if not job then
		job = table.remove(jobs, 1)
		if not job then self:Hide() return end
		local room = P.Progress:Room(job.room)
		if not room then Finish(false) return end
		local ok, b = pcall(R.Parse, R, room)
		if not ok then Finish(false) return end
		job.b, job.s, job.i = b, R:New(b), 0
		return                                  -- parsing was this frame's work
	end
	local j = job
	for _ = 1, MOVES_PER_FRAME do
		j.i = j.i + 1
		if j.s.over or j.i > #j.m then
			Finish(j.s.over == "clear" and j.s.steps == j.steps and j.i - 1 == #j.m)
			return
		end
		if not R:Act(j.b, j.s, j.m:sub(j.i, j.i)) then Finish(false) return end
	end
end)

-- queue a check: moves must clear room `room` in exactly `steps` steps; done(ok) afterwards
local function Check(room, steps, moves, done)
	if type(moves) ~= "string" or #moves == 0 or #moves > MAX_MOVES or moves:find("[^NESW%.]") then
		if done then done(false) end
		return
	end
	if #jobs >= 60 then return end
	jobs[#jobs + 1] = { room = room, steps = steps, m = moves, done = done }
	checker:Show()
end
LB.Check = Check
function LB:Pending() return #jobs + (job and 1 or 0) end

-- ------------------------------------------------------------------ sending (queued, paced, out of combat)
local outq = {}
local sender = CreateFrame("Frame")
sender:Hide()
local nextAt = 0
sender:SetScript("OnUpdate", function(self)
	if #outq == 0 then self:Hide() return end
	if InCombatLockdown and InCombatLockdown() then return end
	local now = GetTime()
	if now < nextAt then return end
	nextAt = now + 0.35
	local m = table.remove(outq, 1)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		local ok, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[1], m[2], m[3])
		if not ok then P:RecordError("leaderboard send", err) end
	end
end)

local function Queue(text, kind, target)
	if #outq >= 120 then return end
	outq[#outq + 1] = { text, kind, target }
	sender:Show()
end

local function ChannelId()
	if not GetChannelName then return nil end
	local id = GetChannelName(CHANNEL)
	return (type(id) == "number" and id > 0) and id or nil
end

local function Targets(only)
	local t = {}
	local id = ChannelId()
	if id and (not only or only == "CHANNEL") then t[#t + 1] = { "CHANNEL", id } end
	if IsInGuild and IsInGuild() and (not only or only == "GUILD") then t[#t + 1] = { "GUILD" } end
	return t
end

local Join
local lastJoin = 0
local function SendEntry(id, e, only)
	-- the shared channel can be gone (Piggle's sharing switched off left it): join it again, at most once a minute
	if not ChannelId() and GetTime() - lastJoin > 60 then lastJoin = GetTime() Join() end
	local body = table.concat({ id, e.s, e.who, e.t or 0, e.m }, SEP)
	local mid = ("%06x"):format(math.random(0, 16777215))
	local n = math.ceil(#body / CHUNK)
	if n > 8 then return end
	for _, tg in ipairs(Targets(only)) do
		for i = 1, n do
			Queue(table.concat({ "E", mid, i, n, body:sub((i - 1) * CHUNK + 1, i * CHUNK) }, SEP), tg[1], tg[2])
		end
	end
end

-- ------------------------------------------------------------------ receiving
local parts = {}      -- sender..mid -> { n, got, [i] = text }
local seenAt = {}     -- id..who..steps -> time last heard (answers skip what was just sent)
local answerAt
local me

local function SeenKey(id, e) return id .. "|" .. e.who .. "|" .. e.s end

local function Parse(body)
	local f = {}
	for x in (body .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = x end
	if #f ~= 5 then return nil end
	local id, s, who, t, m = f[1], tonumber(f[2]), f[3], tonumber(f[4]), f[5]
	if not s or s < 1 or s ~= math.floor(s) or who == "" or #who > 60 or who:find("[|\n]") then return nil end
	return id, { s = s, who = who, t = t, m = m }
end

local function Heard(id, e, kind)
	seenAt[SeenKey(id, e)] = GetTime()
	local room = LB:RoomOf(id)
	if not room then return end
	if not Qualifies(DB()[id] or {}, e) then return end
	if kind == "GUILD" then e.g = true end
	Check(room, e.s, e.m, function(ok) if ok then Insert(id, e) end end)
end

local function Answer(kind)
	answerAt = nil
	local now, sent = GetTime(), 0
	for id, list in pairs(DB()) do
		for i = 1, math.min(3, #list) do
			local e = list[i]
			local k = SeenKey(id, e)
			if not (seenAt[k] and now - seenAt[k] < 60) and sent < 15 then
				seenAt[k] = now
				SendEntry(id, e, kind)
				sent = sent + 1
			end
		end
	end
end

local function OnMessage(_, prefix, text, kind, from)
	if prefix ~= PREFIX or not LB:Enabled() or type(text) ~= "string" then return end
	if from and me and (from == me or from:match("^([^%-]+)") == me:match("^([^%-]+)")) then return end
	local tag = text:sub(1, 1)
	if tag == "Q" then
		if not answerAt and C_Timer and C_Timer.After then
			answerAt = GetTime() + 2 + math.random() * 7
			local reply = kind == "GUILD" and "GUILD" or "CHANNEL"
			C_Timer.After(answerAt - GetTime(), function() P:Safe("leaderboard answer", Answer, reply) end)
		end
	elseif tag == "E" then
		local mid, i, n, chunk = text:match("^E" .. SEP .. "(%x+)" .. SEP .. "(%d+)" .. SEP .. "(%d+)" .. SEP .. "(.*)$")
		i, n = tonumber(i), tonumber(n)
		if not mid or not i or not n or n > 8 or i < 1 or i > n then return end
		local k = (from or "?") .. mid
		local p = parts[k]
		if not p then
			-- forget half-heard messages after a minute
			local now = GetTime()
			for key, q in pairs(parts) do if now - q.t > 60 then parts[key] = nil end end
			p = { n = n, got = 0, t = now }
			parts[k] = p
		end
		if not p[i] then p[i] = chunk p.got = p.got + 1 end
		if p.got == p.n then
			parts[k] = nil
			local id, e = Parse(table.concat(p, "", 1, p.n))
			if id then Heard(id, e, kind) end
		end
	end
end
LB.OnMessage = OnMessage

-- ------------------------------------------------------------------ the hidden channel
local function HideChannel()
	local remove = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or ChatFrame_RemoveChannel
	if not remove then return end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf then pcall(remove, cf, CHANNEL) end
	end
end

local function NoticeFilter(_, _, ...)
	for i = 1, select("#", ...) do
		local a = select(i, ...)
		if type(a) == "string" and a:lower():find(CHANNEL:lower(), 1, true) then return true end
	end
	return false
end

function Join()
	if not LB:Enabled() then return end
	if not ChannelId() then
		local join = JoinTemporaryChannel or JoinChannelByName
		if join then pcall(join, CHANNEL) end
	end
	P:After(2, function()
		HideChannel()
		if NetherChannels and NetherChannels.Settle then NetherChannels:Settle(CHANNEL) end
		if LB:Enabled() then
			for _, tg in ipairs(Targets()) do Queue("Q" .. SEP .. "1", tg[1], tg[2]) end
		end
	end)
end

function LB:SetEnabled(on)
	if on then Join()
	else
		-- the channel is shared: leave it only when no other family game is using it
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
		local piggleOn = loaded and loaded("Piggle")
		local leave = LeaveChannelByName
		if leave and ChannelId() and not piggleOn then pcall(leave, CHANNEL) end
		wipe(outq)
	end
end

-- ------------------------------------------------------------------ this player's clears
function LB:Record(id, steps, moves)
	if P.readOnly or not me then return end
	local c = P.char
	if c and c.edited then return end              -- records still being re-checked after an outside edit
	local e = { who = me, s = steps, t = (GetServerTime and GetServerTime()) or 0, m = moves, g = true }
	if Insert(id, e) and self:Enabled() then SendEntry(id, e) end
end

-- ------------------------------------------------------------------ sealed records
local function Hash(str)
	local h = 7
	for i = 1, #str do h = (h * 31 + str:byte(i)) % 4294967291 end
	return ("%08x"):format(h)
end

local function Digest(c, guid)
	local out = {}
	local ids = {}
	for id in pairs(c.rooms or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local r = c.rooms[id]
		out[#out + 1] = id .. ":" .. tostring(r.best) .. ":" .. tostring(r.medal) .. ":" .. tostring(r.moves)
	end
	local days = {}
	for d in pairs(c.daily or {}) do days[#days + 1] = d end
	table.sort(days)
	for _, d in ipairs(days) do
		local r = c.daily[d]
		out[#out + 1] = d .. ":" .. tostring(r.best) .. ":" .. tostring(r.medal) .. ":" .. tostring(r.moves) .. ":" .. tostring(r.room)
	end
	out[#out + 1] = tostring(c.dailyDays)
	return Hash(table.concat(out, ";") .. guid .. SALT)
end
LB.Digest = Digest

-- an outside edit: every record is replayed; what does not check out is dropped
local function Recheck(c)   -- (LB.Recheck below, for the tests)
	c.edited = true
	local left = 0
	local function Done() left = left - 1 if left == 0 then c.edited = nil end end
	for id, r in pairs(c.rooms) do
		if r.best and r.moves then
			left = left + 1
			local claimed = r.best
			Check(id, claimed, r.moves, function(ok)
				if not ok then c.rooms[id] = nil
				else r.medal = R:Medal(P.Progress:Room(id), claimed) end      -- the medal its best really earns
				Done()
			end)
		else
			c.rooms[id] = nil
		end
	end
	for d, r in pairs(c.daily or {}) do
		if r.best and r.moves and r.room then
			left = left + 1
			Check(r.room, r.best, r.moves, function(ok) if not ok then c.daily[d] = nil end Done() end)
		else
			c.daily[d] = nil
		end
	end
	if left == 0 then c.edited = nil end
end
LB.Recheck = Recheck

-- ------------------------------------------------------------------ start up
P:Register("LOGIN", function()
	local name = UnitName and UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	me = name and (realm and realm ~= "" and (name .. "-" .. realm) or name) or nil
	LB.me = me
	local c = P.char
	if c and c.seal and c.seal ~= Digest(c, P.guid) then P:Safe("records check", Recheck, c) end
	P:Safe("leaderboard prune", Prune)
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
	local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if addFilter then
		for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
			pcall(addFilter, ev, NoticeFilter)
		end
	end
	-- channels are not ready the moment the world loads
	P:After(10, Join)
end)
P:On("CHAT_MSG_ADDON", OnMessage)
P:On("PLAYER_LOGOUT", function()
	local c = P.char
	if c and P.guid and not c.edited and not P.readOnly then c.seal = Digest(c, P.guid) end
end)
