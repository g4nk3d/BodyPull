--[[ Body Pull - UI/Extras.lua
	The screens beyond playing a room: the daily room, scores (Mine / Everyone, with a share-to-chat bar),
	achievements, shields, the game's own settings, and the first-run welcome. Built with the window's
	screens (UI/Window.lua) the first time the window opens; each screen refreshes when shown.

	  G:StartDaily()          play today's daily room
	  G:ShareText(id)         the line the Share button puts in the chat box (the player sends it) ]]

local _, ns = ...
local P = ns.P
local G = P.Game
local A, Au, UI, Pr = P.Assets, P.Audio, P.UI, P.Progress
local floor = math.floor

local SIZES = { { 0.6, "Small" }, { 0.75, "Medium" }, { 0.9, "Large" }, { 1, "Fill the screen" } }

local function SizeName(v)
	for _, s in ipairs(SIZES) do if math.abs(s[1] - (tonumber(v) or 0.9)) < 0.01 then return s[2] end end
	return "Large"
end

local function RoomLabel(id)
	local room = Pr:Room(id)
	if not room then return "?" end
	return ("%s %d. %s"):format(Pr:Delve(room.delve).name, room.index, room.name)
end

-- the board a score list belongs to, as words
local function BoardLabel(id)
	local date = id:match("^" .. P.Daily.BOARD_PREFIX .. "(%d%d%d%d%-%d%d%-%d%d)$")
	if date then
		local room = P.Leaderboard:RoomOf(id)
		return ("Daily room, %s: %s"):format(date, room and Pr:Room(room).name or "?")
	end
	return RoomLabel(id)
end

local function Back() G:Screen("menu") end

local function BackButton(f, fn)
	local b = UI:Wide(f, "Back", 160, fn or Back, "ui_cancel")
	b:SetPoint("BOTTOM", 0, 18)
	return b
end

local function Badge(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.frame = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.frame:SetAllPoints()
	b.art = b:CreateTexture(nil, "ARTWORK", nil, 0)
	b.art:SetPoint("CENTER")
	b.art:SetSize(size * 0.74, size * 0.74)
	return b
end

-- ------------------------------------------------------------------ playing the daily room
function G:StartDaily()
	local date, day = P.Daily:Today()
	local id = P.Daily:RoomId(day)
	if not id then return end
	self:Start(id, nil, date)
end

function G:ShareText(id)
	local mine
	local date = id and id:match("^" .. P.Daily.BOARD_PREFIX .. "(%d%d%d%d%-%d%d%-%d%d)$")
	local medal
	if date then
		local r = P.Daily:Record(date)
		mine, medal = r and r.best, r and r.medal
	else
		local r = Pr:Record(id)
		mine, medal = r and r.best, r and r.medal
	end
	if not mine then return nil end
	local m = ({ "bronze", "silver", "gold" })[medal or 0]
	return ("[Body Pull] %s: cleared in %d steps%s."):format(BoardLabel(id), mine, m and (" (" .. m .. ")") or "")
end

local function OpenChat(text)
	local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
	if not open or not text then Au:Play("ui_error") return end
	G:Close()
	pcall(open, text)
end

-- ------------------------------------------------------------------ building
-- each screen is made the first time it is shown (G:Screen asks G.lazy)
function G:BuildExtras()
	local SF, Ribbon = self.ScreenFrame, self.Ribbon
	local lazy = self.lazy

	lazy.daily = function()
		-- the daily room ------------------------------------------------------------
		local d = SF("daily", 560, 520)
		Ribbon(d, "Daily Room")
		d.card = d:CreateTexture(nil, "ARTWORK")
		A:Sprite(d.card, "daily_card")
		d.card:SetSize(448, 224)
		d.card:SetPoint("TOP", 0, -52)
		d.title = UI:Text(d, 17, "title")
		d.title:SetPoint("TOP", d.card, "BOTTOM", 0, -10)
		d.title:SetWidth(480)
		d.info = UI:Text(d, 13, "light")
		d.info:SetPoint("TOP", d.title, "BOTTOM", 0, -8)
		d.info:SetWidth(480)
		d.info:SetSpacing(4)
		d.play = UI:Wide(d, "Play", 180, function() G:StartDaily() end, "ui_confirm")
		d.play:SetPoint("BOTTOM", d, "BOTTOM", -96, 70)
		local ds = UI:Wide(d, "Scores", 180, function() G.scoreBoard = P.Daily.BOARD_PREFIX .. P.Daily:Today() G.scoreTab = "all" G:Screen("scores") end)
		ds:SetPoint("BOTTOM", d, "BOTTOM", 96, 70)
		BackButton(d)
		function d:Refresh()
			local date, day = P.Daily:Today()
			local id = P.Daily:RoomId(day)
			local room = Pr:Room(id)
			self.title:SetText(("%s  -  %s"):format(date, room and RoomLabel(id) or "?"))
			local rec = P.Daily:Record(date)
			local list = P.Leaderboard:Board(P.Daily.BOARD_PREFIX .. date)
			local guild, all
			for _, e in ipairs(list) do
				if e.g and not guild then guild = e end
				if not all then all = e end
			end
			local lines = {
				("Par %d    Gold %d"):format(room and room.par or 0, room and room.gold or 0),
				rec and rec.best and ("Your best today: %d steps"):format(rec.best) or "You haven't cleared today's room yet.",
			}
			if guild then lines[#lines + 1] = ("Guild best: %d steps (%s)"):format(guild.s, guild.who) end
			if all and all ~= guild then lines[#lines + 1] = ("Best heard: %d steps (%s)"):format(all.s, all.who) end
			local days = P.Daily:DaysCleared()
			lines[#lines + 1] = days < 7 and ("|cffb8a888Days cleared: %d of 7 for Daily Regular.|r"):format(days)
				or ("|cffb8a888Days cleared: %d.|r"):format(days)
			self.info:SetText(table.concat(lines, "\n"))
			self.play:SetLabel(rec and rec.best and "Play again" or "Play")
		end
	end

	lazy.scores = function()
		-- scores --------------------------------------------------------------------
		local sc = SF("scores", 700, 640)
		Ribbon(sc, "Scores")
		sc.tabs = {}
		for i, def in ipairs({ { "mine", "Mine" }, { "all", "Everyone" } }) do
			local t = CreateFrame("Button", nil, sc)
			t:SetSize(170, 38)
			t:SetPoint("TOP", sc, "TOP", (i - 1.5) * 176, -50)
			t.on = UI:Slice3(t, "ARTWORK", 0, "tab_active", 38, 0.2)
			t.off = UI:Slice3(t, "ARTWORK", 0, "tab_inactive", 38, 0.2)
			t.label = UI:Text(t, 13, "light")
			t.label:SetPoint("CENTER", 0, 1)
			t.label:SetText(def[2])
			t:SetScript("OnClick", function() Au:Play("ui_click") G.scoreTab = def[1] sc:Refresh() end)
			t.key = def[1]
			sc.tabs[i] = t
		end
		-- Mine: four delves side by side, ten rooms each
		sc.mine = CreateFrame("Frame", nil, sc)
		sc.mine:SetPoint("TOPLEFT", 24, -100)
		sc.mine:SetPoint("BOTTOMRIGHT", -24, 120)
		sc.cells = {}
		for di, dv in ipairs(Pr:Delves()) do
			local head = UI:Text(sc.mine, 13, "title")
			head:SetPoint("TOPLEFT", (di - 1) * 163, 0)
			head:SetWidth(158)
			head:SetText(dv.name)
			for ri = 1, 10 do
				local row = CreateFrame("Frame", nil, sc.mine)
				row:SetSize(158, 34)
				row:SetPoint("TOPLEFT", (di - 1) * 163, -22 - (ri - 1) * 36)
				row.medal = row:CreateTexture(nil, "ARTWORK")
				row.medal:SetSize(26, 26)
				row.medal:SetPoint("LEFT", 0, 0)
				row.text = UI:Text(row, 11, "light", "LEFT")
				row.text:SetPoint("LEFT", row.medal, "RIGHT", 4, 0)
				row.text:SetWidth(126)
				row.text:SetWordWrap(false)
				row.delve, row.index = dv.id, ri
				sc.cells[#sc.cells + 1] = row
			end
		end
		-- Everyone: one board at a time, arrows to walk through them
		sc.all = CreateFrame("Frame", nil, sc)
		sc.all:SetPoint("TOPLEFT", 24, -100)
		sc.all:SetPoint("BOTTOMRIGHT", -24, 120)
		sc.boardName = UI:Text(sc.all, 15, "title")
		sc.boardName:SetPoint("TOP", 0, -4)
		sc.boardName:SetWidth(520)
		local prev = UI:Square(sc.all, "icon_back", 40, "Previous board", function() sc:Step(-1) end)
		prev:SetPoint("TOPLEFT", 0, 4)
		local nextB = UI:Square(sc.all, "icon_play", 40, "Next board", function() sc:Step(1) end)
		nextB:SetPoint("TOPRIGHT", 0, 4)
		sc.rows = {}
		for i = 1, 10 do
			local r = UI:Text(sc.all, 13, "light", "LEFT")
			r:SetPoint("TOPLEFT", 90, -48 - (i - 1) * 28)
			r:SetWidth(470)
			r:SetWordWrap(false)
			sc.rows[i] = r
		end
		sc.empty = UI:Text(sc.all, 13, "light")
		sc.empty:SetPoint("TOP", 0, -80)
		sc.empty:SetWidth(520)
		sc.status = UI:Text(sc, 11, "light")
		sc.status:SetPoint("BOTTOM", 0, 116)
		sc.status:SetWidth(620)
		sc.status:SetAlpha(0.8)
		-- the share bar: your result for the board shown, put into the chat box for you to send
		sc.share = UI:Wide(sc, "Share", 160, function() OpenChat(G:ShareText(sc.boardId)) end)
		sc.share:SetPoint("BOTTOM", 0, 70)
		UI:Tip(sc.share, "Share", "Puts your result for this board into the chat box. You choose where it goes and press Enter to send it.")
		BackButton(sc)

		local function Boards()
			local list = { P.Daily.BOARD_PREFIX .. P.Daily:Today() }
			for _, dv in ipairs(Pr:Delves()) do
				for _, room in ipairs(Pr:Rooms(dv.id)) do list[#list + 1] = room.id end
			end
			return list
		end
		function sc:Step(dir)
			local list = Boards()
			local at = 1
			for i, id in ipairs(list) do if id == G.scoreBoard then at = i end end
			at = (at - 1 + dir) % #list + 1
			G.scoreBoard = list[at]
			self:Refresh()
		end
		function sc:Refresh()
			local tab = G.scoreTab or "mine"
			for _, t in ipairs(self.tabs) do t.on:SetShown(t.key == tab) t.off:SetShown(t.key ~= tab) end
			self.mine:SetShown(tab == "mine")
			self.all:SetShown(tab == "all")
			if not G.scoreBoard or not P.Leaderboard:RoomOf(G.scoreBoard) then
				G.scoreBoard = G.board and G.board.id or Boards()[1]
			end
			self.boardId = tab == "all" and G.scoreBoard or (G.board and G.board.id)
			if tab == "mine" then
				for _, row in ipairs(self.cells) do
					local room = Pr:Rooms(row.delve)[row.index]
					local rec = room and Pr:Record(room.id)
					local ms = G.MedalSprite(rec and rec.medal, false)
					if ms then A:Sprite(row.medal, ms) row.medal:SetAlpha(1)
					else A:Sprite(row.medal, "medal_bronze_64_not_earned") row.medal:SetAlpha(0.35) end
					if room then
						row.text:SetText(("%d. %s  |cffe8c27a%s|r"):format(row.index, room.name, rec and rec.best and tostring(rec.best) or "-"))
					end
				end
				local cleared, total, silver, gold = 0, 0, 0, 0
				for _, dv in ipairs(Pr:Delves()) do
					local c, t = Pr:Count(dv.id)
					cleared, total = cleared + c, total + t
				end
				silver, gold = P.Awards:MedalCounts()
				self.status:SetText(("%d of %d rooms cleared, %d at silver or better, %d gold."):format(cleared, total, silver, gold))
			else
				local id = G.scoreBoard
				self.boardName:SetText(BoardLabel(id))
				local list = P.Leaderboard:Board(id)
				for i, r in ipairs(self.rows) do
					local e = list[i]
					if e then
						local me = P.Leaderboard.me and e.who == P.Leaderboard.me
						r:SetText(("%2d.   %s%s|r   %d steps%s"):format(i, me and "|cff7fff7f" or "|cffffffff", e.who, e.s, e.g and "   |cff9fd59f(guild)|r" or ""))
					else
						r:SetText("")
					end
				end
				self.empty:SetShown(#list == 0)
				self.empty:SetText(P.Leaderboard:Enabled() and "No scores heard for this board yet. They arrive from other Body Pull players over the next minutes."
					or "Sharing scores is off (Settings).")
				local pend = P.Leaderboard:Pending()
				self.status:SetText(P.Leaderboard:Enabled() and (("Every score is checked by replaying its moves before it shows here.%s"):format(pend > 0 and ("  Checking %d now."):format(pend) or ""))
					or "Sharing scores is off: you see only your own results.")
			end
			self.share:SetEnabled(self.boardId ~= nil and G:ShareText(self.boardId) ~= nil)
		end
		P:Register("LEADERBOARD_CHANGED", function() if sc:IsShown() then sc:Refresh() end end)
	end

	lazy.achievements = function()
		-- achievements ----------------------------------------------------------------
		local ac = SF("achievements", 700, 600)
		Ribbon(ac, "Achievements")
		ac.count = UI:Text(ac, 13, "light")
		ac.count:SetPoint("TOP", 0, -54)
		ac.badges = {}
		for i, a in ipairs(P.Awards.LIST) do
			local b = Badge(ac, 92)
			local row, colN = floor((i - 1) / 5), (i - 1) % 5
			local inRow = row < 2 and 5 or (#P.Awards.LIST - 10)
			b:SetPoint("TOP", ac, "TOP", (colN - (inRow - 1) / 2) * 124, -82 - row * 148)
			b.name = UI:Text(b, 11, "light")
			b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
			b.name:SetWidth(120)
			b.name:SetText(a.name)
			b.id = a.id
			UI:Tip(b, function(self)
				local when = P.char and P.char.ach and P.char.ach[a.id]
				local txt = a.about
				if when and when > 0 and date then txt = txt .. "\n|cff9fd59fEarned " .. date("%Y-%m-%d", when) .. ".|r"
				elseif not when then txt = txt .. "\n|cffb8a888Not earned yet.|r" end
				return a.name, txt
			end)
			ac.badges[i] = b
		end
		BackButton(ac)
		function ac:Refresh()
			local n, total = P.Awards:Count()
			self.count:SetText(("%d of %d earned"):format(n, total))
			for i, a in ipairs(P.Awards.LIST) do
				local b = self.badges[i]
				local has = P.Awards:Has(a.id)
				A:Sprite(b.frame, has and "badge_frame_earned" or "badge_frame_locked")
				A:Sprite(b.art, a.badge)
				b.art:SetDesaturated(not has)
				b.art:SetAlpha(has and 1 or 0.45)
				b.name:SetAlpha(has and 1 or 0.6)
			end
		end
	end

	lazy.shields = function()
		-- shields -----------------------------------------------------------------------
		local sh = SF("shields", 640, 520)
		Ribbon(sh, "Shields")
		sh.note = UI:Text(sh, 12, "light")
		sh.note:SetPoint("TOP", 0, -54)
		sh.note:SetWidth(560)
		sh.note:SetText("Your shield's look. Earn new ones by clearing delves and collecting medals. Click one you have to carry it.")
		sh.items = {}
		for i, k in ipairs(P.Awards.SKINS) do
			local b = CreateFrame("Button", nil, sh)
			b:SetSize(112, 140)
			b:SetPoint("TOP", sh, "TOP", ((i - 1) % 4 - 1.5) * 136, -88 - floor((i - 1) / 4) * 168)
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			A:Sprite(b.sel, "room_marker_current")
			b.sel:SetSize(124, 124)
			b.sel:SetPoint("TOP", 0, 6)
			b.art = b:CreateTexture(nil, "ARTWORK")
			A:Sprite(b.art, "shield_skin_" .. k.id)
			b.art:SetSize(104, 104)
			b.art:SetPoint("TOP")
			b.lock = b:CreateTexture(nil, "OVERLAY")
			A:Sprite(b.lock, "lock")
			b.lock:SetSize(30, 30)
			b.lock:SetPoint("BOTTOMRIGHT", b.art, "BOTTOMRIGHT", -2, 2)
			b.name = UI:Text(b, 12, "light")
			b.name:SetPoint("TOP", b.art, "BOTTOM", 0, -4)
			b.name:SetWidth(130)
			b.name:SetText(k.name)
			b.id = k.id
			b:SetScript("OnClick", function(self)
				if P.Awards:SetSkin(self.id) then Au:Play("ui_confirm") sh:Refresh() else Au:Play("ui_error") end
			end)
			b:SetScript("OnEnter", function(self) self.art:SetVertexColor(1.15, 1.1, 1) end)
			b:SetScript("OnLeave", function(self) self.art:SetVertexColor(1, 1, 1) end)
			UI:Tip(b, function(self)
				local open = P.Awards:SkinOpen(k.id)
				return k.name, k.need .. (open and (P.Awards:Skin() == k.id and "\n|cff9fd59fCarried now.|r" or "\n|cff9fd59fClick to carry it.|r") or "\n|cffb8a888Not earned yet.|r")
			end)
			sh.items[i] = b
		end
		BackButton(sh)
		function sh:Refresh()
			local cur = P.Awards:Skin()
			for _, b in ipairs(self.items) do
				local open = P.Awards:SkinOpen(b.id)
				b.sel:SetShown(b.id == cur)
				b.lock:SetShown(not open)
				b.art:SetDesaturated(not open)
				b.art:SetAlpha(open and 1 or 0.5)
			end
		end
	end

	lazy.settings = function()
		-- settings --------------------------------------------------------------------------
		local st = SF("settings", 540, 560)
		Ribbon(st, "Settings")
		st.checks = {}
		local y = -62
		local function C(key, label, tip)
			local cb = UI:Check(st, label, function() return P:Setting(key) end, function(v) P:SetSetting(key, v) end, tip)
			cb:SetPoint("TOPLEFT", 70, y)
			cb:SetWidth(420)
			y = y - 40
			st.checks[#st.checks + 1] = cb
			return cb
		end
		C("music", "Music")
		C("sound", "Sound effects")
		C("shareScores", "Share scores with other players", "Your best results go to other Body Pull players (the Nether games' shared hidden channel and your guild), and theirs come to you. Every score is checked by replaying it. Off: nothing is sent or received.")
		C("dailyNotice", "Tell me when a new daily room is ready", "A small notice at login when you haven't played today's daily room. Off unless you turn it on.")
		C("nudge", "Remind me after 20 minutes of play", "Brother Aldous suggests a break after twenty minutes with the game open. Off unless you turn it on.")
		C("minimapButton", "Show the minimap button")
		st.size = UI:Wide(st, "Window size: Large", 260, function()
			local cur = tonumber(P:Setting("size")) or 0.9
			local nxt = SIZES[1][1]
			for i, s in ipairs(SIZES) do if math.abs(s[1] - cur) < 0.01 then nxt = SIZES[i % #SIZES + 1][1] end end
			P:SetSetting("size", nxt)
			st:Refresh()
		end)
		st.size:SetPoint("TOP", st, "TOP", 0, y - 14)
		local hint = UI:Text(st, 11, "light")
		hint:SetPoint("TOP", st.size, "BOTTOM", 0, -10)
		hint:SetWidth(440)
		hint:SetText("Commands: /bodypull (or /bpull), /bodypull perf, /bodypull debug, /bodypull reset.")
		hint:SetAlpha(0.8)
		BackButton(st)
		function st:Refresh()
			for _, cb in ipairs(self.checks) do cb:Refresh() end
			self.size:SetLabel("Window size: " .. SizeName(P:Setting("size")))
		end
	end

	lazy.welcome = function()
		-- first-run welcome -------------------------------------------------------------------
		local wl = SF("welcome", 600, 500)
		Ribbon(wl, "Welcome")
		local wt = UI:Text(wl, 13, "light")
		wt:SetPoint("TOP", 0, -62)
		wt:SetWidth(520)
		wt:SetSpacing(4)
		wt:SetText("You are the new tank of the Lantern Company.\n\nYou can't push anything: you can only pull. Step close enough for a pack to see you, then lead it back to your party's rug, where Kesk and Wyn finish it off while Brother Aldous keeps you standing.\n\nEvery room can be solved, and undo is free.")
		local wq = UI:Text(wl, 14, "title")
		wq:SetPoint("TOP", wt, "BOTTOM", 0, -18)
		wq:SetText("How big should the game window be?")
		for i, s in ipairs(SIZES) do
			local b = UI:Wide(wl, s[2], 200, function()
				P:SetSetting("size", s[1])
				if P.db then P.db.welcomed = true end
				G:Screen("menu")
			end, "ui_confirm")
			b:SetPoint("TOP", wq, "BOTTOM", ((i - 1) % 2 - 0.5) * 212, -14 - floor((i - 1) / 2) * 58)
		end
	end

end

-- ------------------------------------------------------------------ the daily-room notice (off by default)
local toast
local function ShowToast()
	if not toast then
		toast = CreateFrame("Button", nil, UIParent)
		toast:SetSize(400, 75)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
		toast:SetFrameStrata("DIALOG")
		UI:Slice3(toast, "ARTWORK", 0, "toast", 75, 0.25)
		toast.icon = toast:CreateTexture(nil, "OVERLAY")
		A:Sprite(toast.icon, "game_icon_daily")
		toast.icon:SetSize(44, 44)
		toast.icon:SetPoint("LEFT", 26, 0)
		toast.text = UI:Text(toast, 13, "light", "LEFT")
		toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 10, 0)
		toast.text:SetWidth(300)
		toast:SetScript("OnClick", function(self)
			self:Hide()
			G:Open()
			if G:IsOpen() then G:Screen("daily") end
		end)
	end
	local date, day = P.Daily:Today()
	local room = Pr:Room(P.Daily:RoomId(day))
	toast.text:SetText(("Body Pull: today's daily room is ready.\n|cffe8c27a%s|r  (click to play)"):format(room and room.name or "?"))
	toast:Show()
	Au:Play("ui_toast")
	P:After(10, function() if toast then toast:Hide() end end)
end
G.ShowDailyToast = ShowToast

P:Register("LOGIN", function()
	P:After(15, function()
		if not P:Setting("dailyNotice") then return end
		if InCombatLockdown and InCombatLockdown() then return end
		if P.Daily:Record() then return end
		ShowToast()
	end)
end)
