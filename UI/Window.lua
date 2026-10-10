--[[ Body Pull - UI/Window.lua
	The game window: the board, the HUD, the screens (menu, rooms, results, how to play, paused),
	keyboard and mouse, combat safety and the one OnUpdate driver.

	  G:Open() / G:Close() / G:Toggle()
	  G:Start(roomId [, moves])   play a room (moves: replay a saved run, e.g. after /reload)
	  G:Do(action)                one turn: "N" "E" "S" "W" "." ; G:Undo() ; G:Restart() ; G:Hint()
	  G:Screen(name)              show a screen over the board (nil = back to the board)
	  G:FitScale()                the window's size on this screen
	  G:Perf()                    the /bodypull perf readout

	States: Menu -> Playing (turns) -> Results (clear or wipe) -> Playing / Menu. Combat at any time:
	the run is frozen as it is, the keyboard is let go and the window hides; after combat it comes back
	paused and only a click on Resume continues. The current run is kept move by move in the saved
	data, so a /reload (or a disconnect) comes back to the same turn. ]]

local _, ns = ...
local P = ns.P
local G = P:Module("Game")
local A, Au, UI, Bd, Pr = P.Assets, P.Audio, P.UI, P.Board, P.Progress
local R = ns.Rules

local floor, max, min = math.floor, math.max, math.min
local WIN_W, WIN_H = 1000, 700
local BOARD_W, BOARD_H = 676, 470

local W            -- the window, built on first open
local hud = {}
local screens = {}
local board, s     -- current room and state
-- undo: one entry per turn. A number n means "the first n moves" (always a prefix of the current moves);
-- a string is the whole run before a Restart. The rules are deterministic, so a state is rebuilt by replay.
local undo = {}
local checkpoints = {}   -- { moves = prefix, snap } every CHECK_EVERY turns, so an undo replays at most a few turns
local CHECK_EVERY = 12
local moves = ""
local walk, walkN = {}, 0
local bark = { t = 0 }
local perf = { n = 0, sum = 0, max = 0, over = 0, tags = {} }   -- tags: what over-budget frames were doing

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- ------------------------------------------------------------------ helpers
local function Panel(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f:EnableMouse(true)
	UI:Slice9(f, "BACKGROUND", 0, "inner_panel", 40, 64)
	return f
end

local MEDAL = { "bronze", "silver", "gold" }
local function MedalSprite(m, big)
	if not m or m < 1 then return nil end
	return ("medal_%s_%s_earned"):format(MEDAL[m], big and "256" or "64")
end

-- ------------------------------------------------------------------ barks
local BARKS = {
	nosight = { "aldous", "worried", { "I can't see you!", "Mind the corner...", "Come back where I can see you!" } },
	big = { "wyn", "happy", { "Bigger pull! Bigger!", "Ooh, all of them!" } },
	two = { "kesk", "smug", { "One at a time, mon.", "Easy now. Bring them slow." } },
	clear = { "kesk", "happy", { "Clean work.", "That's how it's done." } },
	gold = { "wyn", "happy", { "Perfect! Not a step wasted!", "Gold! Can we go again?" } },
	wipe = { "aldous", "worried", { "Oh dear. Again?", "I'm so sorry... let's try again." } },
	hint = { "aldous", "smug", { "Try this way, I think." } },
	lost = { "aldous", "worried", { "We've strayed from my plan. Undo back, or start again." } },
	nudge = { "aldous", "happy", { "We've been at this twenty minutes. Stretch your legs?" } },
	low = { "aldous", "worried", { "You're hurt! Back to me!" } },
}
local barkTurn = 0

local function Bark(kind, force)
	local b = BARKS[kind]
	if not b or not hud.bark then return end
	if not force and bark.t > 0 and bark.kind == kind then return end
	local lines = b[3]
	barkTurn = barkTurn + 1
	local text = lines[(barkTurn % #lines) + 1]
	A:Sprite(hud.portrait, b[1] .. "_portrait_" .. b[2])
	hud.barkText:SetText(text)
	hud.bark:Show()
	bark.t, bark.kind = 3.2, kind
end

-- ------------------------------------------------------------------ HUD
local function UpdateHUD(ev)
	if not s then return end
	hud.steps:SetText(("Steps  %d"):format(s.steps))
	hud.par:SetText(board.par and ("Par %d   Gold %d"):format(board.par, board.gold or board.par) or "")
	local healed, hurt = false, false
	if ev then
		for _, e in ipairs(ev) do
			if e[1] == "heal" then healed = true end
			if e[1] == "hit" or e[1] == "cast" then hurt = true end
		end
	end
	for i = 1, R.MAX_PIPS do
		local p = hud.pips[i]
		local name
		if i <= s.pips then
			name = (healed and i == s.pips) and "shield_pip_healing" or "shield_pip_full"
		else
			name = (hurt and i == s.pips + 1) and "shield_pip_lost" or "shield_pip_empty"
		end
		A:Sprite(p, name)
	end
	local rec = G.daily and P.Daily:Record(G.daily) or Pr:Record(board.id)
	hud.best:SetText(rec and rec.best and ((G.daily and "Your best today: %d" or "Your best: %d"):format(rec.best)) or "Not cleared yet")
	hud.undo:SetEnabled(#undo > 0)
	local skin = P.Awards:Skin()
	if hud.shieldId ~= skin then
		hud.shieldId = skin
		A:Sprite(hud.shield, "shield_skin_" .. skin)
	end
end
P:Register("SKIN_CHANGED", function() if s then UpdateHUD() end end)

-- ------------------------------------------------------------------ building
local function Build()
	W = CreateFrame("Frame", nil, UIParent)
	G.W = W
	W:SetSize(WIN_W, WIN_H)
	W:SetPoint("CENTER")
	W:SetFrameStrata("HIGH")
	W:SetToplevel(true)
	W:SetClampedToScreen(true)
	W:SetMovable(true)
	W:EnableMouse(true)
	W:Hide()

	-- the dungeon surround behind everything, then the carved frame
	local bg = W:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetPoint("TOPLEFT", 14, -14)
	bg:SetPoint("BOTTOMRIGHT", -14, 14)
	A:Sprite(bg, "BG_candlewick")
	bg:SetVertexColor(0.8, 0.8, 0.8)
	hud.bg = bg
	local frame = CreateFrame("Frame", nil, W)
	frame:SetAllPoints()
	frame:SetFrameLevel(W:GetFrameLevel() + 40)
	local border = UI:Slice9(frame, "BORDER", 0, "main_window", 44, 64)
	border[5]:Hide()     -- only the frame is drawn: its middle stays open over the board

	-- the title plate (drag here to move the window)
	local drag = CreateFrame("Frame", nil, W)
	drag:SetPoint("TOPLEFT", 40, -10)
	drag:SetPoint("TOPRIGHT", -60, -10)
	drag:SetHeight(64)
	drag:SetFrameLevel(W:GetFrameLevel() + 41)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() if not InCombat() then W:StartMoving() end end)
	drag:SetScript("OnDragStop", function()
		W:StopMovingOrSizing()
		local p, _, rp, x, y = W:GetPoint(1)
		P.db.window = { p, rp, x, y }
	end)
	local plate = drag:CreateTexture(nil, "ARTWORK")
	A:Sprite(plate, "room_title_plate")
	plate:SetSize(640, 80)
	plate:SetPoint("TOP", drag, "TOP", 0, 6)
	-- light lettering with a dark outline on the wooden plank, kept between the lantern caps
	hud.title = UI:Text(drag, 19, "light")
	hud.title:SetTextColor(1, 0.94, 0.78)
	hud.title:SetShadowOffset(2, -2)
	hud.title:SetPoint("CENTER", plate, "CENTER", 0, 1)
	hud.title:SetWidth(480)
	hud.title:SetWordWrap(false)
	local close = UI:Close(drag, function() G:Close() end)
	close:SetPoint("TOPRIGHT", W, "TOPRIGHT", -16, -16)
	close:SetFrameLevel(W:GetFrameLevel() + 42)
	UI:Tip(close, "Close", "Your run is kept: open Body Pull again to carry on.")

	-- the board
	Bd:Build(W, BOARD_W, BOARD_H)
	Bd.area:SetPoint("TOPLEFT", W, "TOPLEFT", 30, -96)
	Bd.area:SetFrameLevel(W:GetFrameLevel() + 2)
	Bd.onDone = function() G:TurnDone() end
	Bd.onHover = function(x, y) G:Hover(x, y) end
	Bd.frame:SetScript("OnMouseDown", function(_, button) G:Click(button) end)

	-- the HUD column
	local col = CreateFrame("Frame", nil, W)
	col:SetPoint("TOPLEFT", W, "TOPLEFT", 724, -92)
	col:SetSize(250, 580)
	col:SetFrameLevel(W:GetFrameLevel() + 42)
	hud.col = col
	local stepPlate = CreateFrame("Frame", nil, col)
	stepPlate:SetSize(250, 62)
	stepPlate:SetPoint("TOP")
	UI:Slice3(stepPlate, "ARTWORK", 0, "step_plate", 62, 0.25)
	hud.steps = UI:Text(stepPlate, 20, "light")
	hud.steps:SetPoint("CENTER", 0, 1)
	hud.par = UI:Text(col, 13, "title")
	hud.par:SetPoint("TOP", stepPlate, "BOTTOM", 0, -4)
	hud.best = UI:Text(col, 12, "light")
	hud.best:SetPoint("TOP", hud.par, "BOTTOM", 0, -3)
	-- your shield (its skin) beside the five pips
	hud.shield = col:CreateTexture(nil, "ARTWORK")
	hud.shield:SetSize(50, 50)
	hud.shield:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -120)
	local shieldTip = CreateFrame("Frame", nil, col)
	shieldTip:SetAllPoints(hud.shield)
	shieldTip:EnableMouse(true)
	UI:Tip(shieldTip, function() return P.Awards:SkinName(P.Awards:Skin()) .. " shield", "Earn new shields by clearing delves and collecting medals (Menu > Shields)." end)
	hud.pips = {}
	for i = 1, R.MAX_PIPS do
		local p = col:CreateTexture(nil, "ARTWORK")
		p:SetSize(36, 36)
		p:SetPoint("TOPLEFT", col, "TOPLEFT", 58 + (i - 1) * 38, -127)
		hud.pips[i] = p
	end
	local pipTip = CreateFrame("Frame", nil, col)
	pipTip:SetPoint("TOPLEFT", hud.pips[1], "TOPLEFT")
	pipTip:SetPoint("BOTTOMRIGHT", hud.pips[R.MAX_PIPS], "BOTTOMRIGHT")
	pipTip:EnableMouse(true)
	UI:Tip(pipTip, "Your shield", "Each mob next to you hits for 1 a turn; a finished cast hits for 2. Brother Aldous heals 1 a turn while he can see you, within 4 tiles of the rug's centre. At 0 the party wipes.")

	local bs = 56
	local function Btn(i, icon, tip, fn)
		local b = UI:Square(col, icon, bs, tip, fn)
		b:SetPoint("TOP", col, "TOP", ((i - 1) % 4 - 1.5) * (bs + 6), -186 - floor((i - 1) / 4) * (bs + 6))
		return b
	end
	hud.undo = Btn(1, "game_icon_undo", "Undo  (Z or Backspace)", function() G:Undo() end)
	hud.wait = Btn(2, "game_icon_wait", "Wait a turn  (Space)", function() G:Do(".") end)
	hud.restart = Btn(3, "game_icon_restart", "Restart the room  (R)\nUndo brings your run back.", function() G:Restart() end)
	hud.hint = Btn(4, "game_icon_hint", "Lantern hint  (H)", function() G:Hint() end)

	local keys = UI:Text(col, 11, "light", "LEFT")
	keys:SetPoint("TOPLEFT", col, "TOPLEFT", 6, -258)
	keys:SetWidth(240)
	keys:SetSpacing(3)
	keys:SetText("|cffe8c27aMove|r  WASD or arrows, or click a tile\n|cffe8c27aWait|r  Space    |cffe8c27aUndo|r  Z    |cffe8c27aRestart|r  R\nLead mobs into the green party ring.\nHover a mob to see its ring.")
	keys:SetAlpha(0.85)

	-- the party's barks: portrait and speech bubble
	local bk = CreateFrame("Frame", nil, col)
	bk:SetSize(250, 96)
	bk:SetPoint("TOP", col, "TOP", 0, -340)
	hud.bark = bk
	hud.portrait = bk:CreateTexture(nil, "ARTWORK")
	hud.portrait:SetSize(78, 78)
	hud.portrait:SetPoint("LEFT", 0, 0)
	local bubble = CreateFrame("Frame", nil, bk)
	bubble:SetPoint("TOPLEFT", hud.portrait, "TOPRIGHT", 2, 6)
	bubble:SetSize(170, 84)
	-- the bubble's 9-slice: left 48, top 16, right 16, bottom 32 in the source (the tail sits left)
	UI:Slice9(bubble, "ARTWORK", 0, "bark_bubble", 18, 24)
	hud.barkText = UI:Text(bubble, 12, "ink", "LEFT")
	hud.barkText:SetPoint("TOPLEFT", 16, -12)
	hud.barkText:SetPoint("BOTTOMRIGHT", -12, 16)
	hud.barkText:SetJustifyV("MIDDLE")
	bk:Hide()

	local rooms = UI:Wide(col, "Rooms", 160, function() G:Screen("rooms") end)
	rooms:SetPoint("TOP", col, "TOP", 0, -452)
	local menu = UI:Wide(col, "Menu", 160, function() G:Screen("menu") end)
	menu:SetPoint("TOP", rooms, "BOTTOM", 0, -4)

	-- the screens' shade
	local shade = CreateFrame("Frame", nil, W)
	shade:SetPoint("TOPLEFT", 16, -16)
	shade:SetPoint("BOTTOMRIGHT", -16, 16)
	shade:SetFrameLevel(W:GetFrameLevel() + 50)
	shade:EnableMouse(true)
	local sh = shade:CreateTexture(nil, "BACKGROUND")
	sh:SetAllPoints()
	sh:SetColorTexture(0.03, 0.02, 0.02, 0.72)
	shade:Hide()
	G.shade = shade

	-- input
	W:SetScript("OnKeyDown", function(self, key)
		if InCombat() then return end
		local handled = G:Key(key)
		self:SetPropagateKeyboardInput(not handled)
	end)
	W:SetScript("OnShow", function() G:Shown() end)
	W:SetScript("OnHide", function() G:Hidden() end)
	G:BuildScreens()
	G:FitScale()
	local wp = P.db.window
	if type(wp) == "table" and type(wp[1]) == "string" and type(wp[3]) == "number" and type(wp[4]) == "number" then
		W:ClearAllPoints()
		if not pcall(W.SetPoint, W, wp[1], UIParent, wp[2] or wp[1], wp[3], wp[4]) then W:SetPoint("CENTER") end
	end
end

-- ------------------------------------------------------------------ screens
local function ScreenFrame(name, w, h)
	local f = Panel(G.shade, w, h)
	f:SetPoint("CENTER", G.shade, "CENTER")
	f:SetFrameLevel(G.shade:GetFrameLevel() + 2)
	f:Hide()
	screens[name] = f
	return f
end

-- the screen title on the scroll ribbon. Only the open parchment between the two rolled ends takes
-- text: measured on the art, it spans x 324..693 of 1024 at its middle row (y 88 of 192), so the
-- words are centred there and shrink until they fit inside it.
local RIBBON_W, RIBBON_H = 520, 98
local PARCH_W = (693 - 324) / 1024 * RIBBON_W - 14
local PARCH_DY = (96 - 88) / 192 * RIBBON_H

local function FitRibbon(fs, text)
	fs:SetText(text)
	for size = 22, 11, -1 do
		local font, _, flags = fs:GetFont()
		fs:SetFont(font, size, flags)
		local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
		if w <= PARCH_W then break end
	end
end

local function Ribbon(parent, text)
	local r = parent:CreateTexture(nil, "ARTWORK")
	A:Sprite(r, "title_ribbon")
	r:SetSize(RIBBON_W, RIBBON_H)
	r:SetPoint("TOP", parent, "TOP", 0, 44)
	local fs = UI:Text(parent, 22, "ink")
	fs:SetPoint("CENTER", r, "CENTER", 0, PARCH_DY)
	fs:SetWordWrap(false)
	fs.SetTitle = FitRibbon
	FitRibbon(fs, text)
	parent.ribbon = fs
	return fs
end

G.ScreenFrame, G.Ribbon, G.MedalSprite, G.screens = ScreenFrame, Ribbon, MedalSprite, screens
G.lazy = {}        -- name -> builds that screen the first time it is shown (UI/Extras.lua)

function G:BuildScreens()
	-- main menu
	local m = ScreenFrame("menu", 500, 540)
	Ribbon(m, "Body Pull")
	local logo = m:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(P.MEDIA .. "Logo")
	logo:SetSize(128, 128)
	logo:SetPoint("TOP", 0, -50)
	local tag = UI:Text(m, 13, "light")
	tag:SetPoint("TOP", logo, "BOTTOM", 0, -6)
	tag:SetWidth(360)
	tag:SetText("You can't push anything. You can only pull.")
	-- two columns of buttons; Close alone at the bottom
	local n = 0
	local function MB2(label, fn)
		local b = UI:Wide(m, label, 200, fn)
		b:SetPoint("TOP", m, "TOP", (n % 2 - 0.5) * 212, -226 - floor(n / 2) * 56)
		n = n + 1
		return b
	end
	m.cont = MB2("Continue", function() G:Screen(nil) end)
	MB2("Rooms", function() G:Screen("rooms") end)
	MB2("Daily Room", function() G:Screen("daily") end)
	MB2("How to Play", function() G:Screen("help") end)
	MB2("Scores", function() G:Screen("scores") end)
	MB2("Achievements", function() G:Screen("achievements") end)
	MB2("Shields", function() G:Screen("shields") end)
	MB2("Settings", function() G:Screen("settings") end)
	local close = UI:Wide(m, "Close", 200, function() G:Close() end)
	close:SetPoint("TOP", m, "TOP", 0, -226 - 4 * 56)

	-- rooms: a tab per delve, the delve's entrance card, its ten room markers
	local r = ScreenFrame("rooms", 660, 650)
	Ribbon(r, "Choose a Room")
	r.tabs = {}
	for i, d in ipairs(Pr:Delves()) do
		local t = CreateFrame("Button", nil, r)
		t:SetSize(150, 38)
		t:SetPoint("TOP", r, "TOP", (i - 2.5) * 154, -50)
		t.on = UI:Slice3(t, "ARTWORK", 0, "tab_active", 38, 0.2)
		t.off = UI:Slice3(t, "ARTWORK", 0, "tab_inactive", 38, 0.2)
		t.hov = UI:Slice3(t, "ARTWORK", 1, "tab_hover", 38, 0.2)
		t.hov:Hide()
		t.label = UI:Text(t, 12, "light")
		t.label:SetPoint("CENTER", 0, 1)
		t.label:SetText(d.name)
		t.lock = t:CreateTexture(nil, "OVERLAY")
		A:Sprite(t.lock, "lock")
		t.lock:SetSize(18, 18)
		t.lock:SetPoint("RIGHT", t.label, "LEFT", -2, 0)
		t.delve = d.id
		t:SetScript("OnEnter", function(self) self.hov:Show() Au:Play("ui_hover") end)
		t:SetScript("OnLeave", function(self) self.hov:Hide() end)
		t:SetScript("OnClick", function(self)
			if not Pr:DelveOpen(self.delve) then Au:Play("ui_error") return end
			Au:Play("ui_click")
			G.roomsDelve = self.delve
			G:RefreshRooms()
		end)
		UI:Tip(t, function(self)
			if Pr:DelveOpen(self.delve) then return nil end
			local prev = Pr:Delves()[i - 1]
			return d.name, ("Clear the last room of %s to open it."):format(prev and prev.name or "the delve before")
		end)
		r.tabs[i] = t
	end
	local card = r:CreateTexture(nil, "ARTWORK")
	card:SetSize(448, 224)
	card:SetPoint("TOP", 0, -94)
	r.card = card
	-- the card's blank panel (right of its picture: x 310..480, y 40..210 of 512 x 256) takes the text
	r.delveName = UI:Text(r, 15, "title", "LEFT")
	r.delveName:SetPoint("TOPLEFT", card, "TOPLEFT", 276, -40)
	r.delveName:SetWidth(138)
	r.delveInfo = UI:Text(r, 11, "light", "LEFT")
	r.delveInfo:SetPoint("TOPLEFT", r.delveName, "BOTTOMLEFT", 0, -8)
	r.delveInfo:SetWidth(138)
	r.markers = {}
	for i = 1, 10 do
		local b = CreateFrame("Button", nil, r)
		b:SetSize(76, 76)
		b:SetPoint("TOP", r, "TOP", ((i - 1) % 5 - 2) * 108, -334 - floor((i - 1) / 5) * 120)
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetAllPoints()
		b.num = UI:Text(b, 20, "title")
		b.num:SetPoint("CENTER", 0, 2)
		b.medal = b:CreateTexture(nil, "OVERLAY")
		b.medal:SetSize(30, 30)
		b.medal:SetPoint("BOTTOMRIGHT", 6, -4)
		b.name = UI:Text(b, 11, "light")
		b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
		b.name:SetWidth(100)
		b.name:SetHeight(26)
		b.name:SetJustifyV("TOP")
		b:SetScript("OnClick", function(self)
			if self.locked then Au:Play("ui_error") return end
			Au:Play("ui_confirm")
			G:Start(self.id)
		end)
		b:SetScript("OnEnter", function(self) Au:Play("ui_hover") self.art:SetVertexColor(1.15, 1.1, 1) end)
		b:SetScript("OnLeave", function(self) self.art:SetVertexColor(1, 1, 1) end)
		UI:Tip(b, function(self)
			local room = Pr:Room(self.id)
			if not room then return nil end
			local rec = Pr:Record(self.id)
			local t = self.locked and "Clear the room before this one to open it." or
				(("Par %d, gold %d.%s"):format(room.par or 0, room.gold or 0, rec and rec.best and ("\nYour best: " .. rec.best) or ""))
			return room.index .. ". " .. room.name, t
		end)
		r.markers[i] = b
	end
	local back = UI:Wide(r, "Back", 160, function() G:Screen(G.s and not G.s.over and nil or "menu") end, "ui_cancel")
	back:SetPoint("BOTTOM", 0, 18)
	r:SetScript("OnShow", function() G:RefreshRooms() end)

	-- results
	local res = ScreenFrame("results", 560, 540)
	res.title = Ribbon(res, "Room Cleared!")
	res.art = res:CreateTexture(nil, "ARTWORK")
	res.art:SetSize(440, 220)
	res.art:SetPoint("TOP", 0, -40)
	res.medal = res:CreateTexture(nil, "OVERLAY")
	res.medal:SetSize(96, 96)
	res.medal:SetPoint("TOPRIGHT", res.art, "TOPRIGHT", 10, 10)
	res.line1 = UI:Text(res, 20, "title")
	res.line1:SetPoint("TOP", res.art, "BOTTOM", 0, -10)
	res.line2 = UI:Text(res, 13, "light")
	res.line2:SetPoint("TOP", res.line1, "BOTTOM", 0, -6)
	res.line2:SetWidth(480)
	-- what this clear earned: achievements (badges) and new shields
	res.awards = UI:Text(res, 13, "title")
	res.awards:SetPoint("TOP", res.line2, "BOTTOM", 0, -10)
	res.awards:SetWidth(500)
	res.badges = {}
	for i = 1, 4 do
		local t = res:CreateTexture(nil, "OVERLAY")
		t:SetSize(52, 52)
		res.badges[i] = t
	end
	res.a = UI:Wide(res, "Next Room", 160, function() G:ResultA() end, "ui_confirm")
	res.a:SetPoint("BOTTOM", res, "BOTTOM", -170, 22)
	res.b = UI:Wide(res, "Retry", 160, function() G:Restart() end)
	res.b:SetPoint("BOTTOM", res, "BOTTOM", 0, 22)
	res.c = UI:Wide(res, "Rooms", 160, function() G:Screen("rooms") end)
	res.c:SetPoint("BOTTOM", res, "BOTTOM", 170, 22)

	-- how to play
	local h = ScreenFrame("help", 620, 540)
	Ribbon(h, "How to Play")
	local txt = UI:Text(h, 13, "light", "LEFT")
	txt:SetPoint("TOPLEFT", 40, -56)
	txt:SetWidth(540)
	txt:SetSpacing(4)
	txt:SetText(table.concat({
		"|cffe8c27aYou are the tank.|r You can't push anything: you can only pull. Clear each room by leading the sleeping mobs back to your party's rug.",
		"",
		"|cffe8c27aYour turn:|r step one tile (WASD or arrows) or wait (Space). Click a tile to walk there; the walk stops the moment anything wakes.",
		"|cffe8c27aWaking:|r a sleeping mob wakes when you step inside its ring and it can see you. Walls and pillars block sight; carts and crates don't. Chained mobs wake together.",
		"|cffe8c27aTheir turn:|r every awake mob steps toward you. Rats run two tiles. Geomancers stop and cast when they can see you within 3 tiles: a finished cast hits for 2, unless you break their sight first.",
		"|cffe8c27aYour shield:|r 5 pips. Each mob next to you hits for 1 a turn. Brother Aldous heals 1 a turn while he can see you, within 4 tiles.",
		"|cffe8c27aKilling:|r the green ring around the rug is the party ring. While you stand inside it, Kesk and Wyn hit a mob inside it every turn: most die in two hits.",
		"",
		"Bronze for a clear, silver at par, gold at the best possible step count. Undo is free (Z), restart is instant (R). Nothing is random: every room can be solved.",
	}, "\n"))
	local hb = UI:Wide(h, "Back", 160, function() G:Screen(G.s and not G.s.over and nil or "menu") end, "ui_cancel")
	hb:SetPoint("BOTTOM", 0, 18)

	-- paused for combat
	local pz = ScreenFrame("paused", 460, 260)
	Ribbon(pz, "Paused")
	pz.text = UI:Text(pz, 14, "light")
	pz.text:SetPoint("TOP", 0, -64)
	pz.text:SetWidth(380)
	pz.resume = UI:Wide(pz, "Resume", 180, function()
		if InCombat() then Au:Play("ui_error") return end
		G:Screen(G.s and not G.s.over and nil or "menu")
		G:Keyboard(true)
	end, "ui_confirm")
	pz.resume:SetPoint("BOTTOM", 0, 26)

	-- the daily room, scores, achievements, shields, settings, welcome (UI/Extras.lua)
	if G.BuildExtras then G:BuildExtras() end
end

function G:RefreshRooms()
	local r = screens.rooms
	local delve = G.roomsDelve or (board and board.delve) or "candlewick"
	if not Pr:DelveOpen(delve) then delve = "candlewick" end
	G.roomsDelve = delve
	local d = Pr:Delve(delve)
	for _, t in ipairs(r.tabs) do
		local open, sel = Pr:DelveOpen(t.delve), t.delve == delve
		t.on:SetShown(sel)
		t.off:SetShown(not sel)
		t.lock:SetShown(not open)
		t.label:SetAlpha(open and 1 or 0.5)
	end
	A:Sprite(r.card, delve .. "_entrance_card")
	r.delveName:SetText(d.name)
	local list = Pr:Rooms(delve)
	local cleared, total, medals = Pr:Count(delve)
	r.delveInfo:SetText(("%d / %d rooms cleared\n%d / %d medal points\n\n%s"):format(cleared, total, medals, total * 3, d.about or ""))
	local current
	for i, b in ipairs(r.markers) do
		local room = list[i]
		b:SetShown(room ~= nil)
		if room then
			b.id = room.id
			b.locked = not Pr:Unlocked(room.id)
			local rec = Pr:Record(room.id)
			local medal = rec and rec.medal or 0
			local art = "room_marker_open"
			if b.locked then art = "room_marker_locked"
			elseif medal == 3 then art = "room_marker_gold"
			elseif medal == 2 then art = "room_marker_silver"
			elseif medal == 1 then art = "room_marker_bronze"
			elseif not current then art = "room_marker_current" current = i end
			A:Sprite(b.art, art)
			b.num:SetText(b.locked and "" or tostring(i))
			b.name:SetText(room.name)
			b.name:SetAlpha(b.locked and 0.5 or 1)
			local ms = MedalSprite(medal)
			if ms then A:Sprite(b.medal, ms) b.medal:Show() else b.medal:Hide() end
		end
	end
end

function G:Screen(name)
	if not W then return end
	if name and not screens[name] and G.lazy[name] then
		local build = G.lazy[name]
		G.lazy[name] = nil
		P:Safe("build " .. name, build)
	end
	for k, f in pairs(screens) do f:SetShown(k == name) end
	self.screen = name
	G.shade:SetShown(name ~= nil)
	if name then
		self:StopWalk()
		Bd:ClearHover()
		Au:Play("ui_menu_open")
		if name == "menu" then screens.menu.cont:SetEnabled(G.s ~= nil and not G.s.over) end
		local f = screens[name]
		if f and f.Refresh then P:Safe("screen " .. name, f.Refresh, f) end
	end
	if name and name ~= "results" and name ~= "paused" and name ~= "help" then Au:Music("music_lantern_company")
	elseif not name and board then Au:Music("music_" .. (board.delve or "candlewick")) end
end

-- ------------------------------------------------------------------ the run
local function SaveRun()
	if P.char and not P.readOnly then
		P.char.resume = board and { id = board.id, moves = moves, daily = G.daily } or nil
	end
end

-- daily: the date when this is that day's daily room (its records are kept apart from the campaign)
function G:Start(id, replay, daily)
	local b = Pr:Board(id)
	if not b then return end
	if not W then Build() end
	G.daily = daily
	board = b
	G.board = b
	s = R:New(b)
	G.s = s
	wipe(undo)
	wipe(checkpoints)
	moves = ""
	-- a saved run: replay its moves silently (rules are deterministic), keeping undo history
	if replay and replay ~= "" then
		for i = 1, #replay do
			local a = replay:sub(i, i)
			if s.over or not R:Act(b, s, a) then break end
			undo[#undo + 1] = #moves
			moves = moves .. a
			if #moves % CHECK_EVERY == 0 then checkpoints[#checkpoints + 1] = { moves = moves, snap = R:Copy(s) } end
		end
	end
	local room = Pr:Room(id)
	if daily then
		hud.title:SetText(("Daily Room  -  %s"):format(room.name))
	else
		hud.title:SetText(("%s  -  %d. %s"):format(Pr:Delve(b.delve).name, room.index, room.name))
	end
	G.roomsDelve = b.delve
	A:Sprite(hud.bg, "BG_" .. (b.delve or "candlewick"))
	Bd:Load(b, s)
	Bd.hadSight = nil
	UpdateHUD()
	hud.bark:Hide()
	bark.t = 0
	SaveRun()
	if s.over then self:ShowResult() else self:Screen(nil) end
	if room.index == 1 and #moves == 0 and not daily then
		hud.portrait:Show()
		A:Sprite(hud.portrait, "aldous_portrait_happy")
		hud.barkText:SetText(room.hint)
		hud.bark:Show()
		bark.t, bark.kind = 6, "intro"
	end
end

local evBuf
function G:Do(action)
	if not s or s.over or self.screen or InCombat() then return false end
	if Bd:Busy() then Bd:Finish() end
	if s.over then return false end
	local snap = R:Copy(s)
	local ev = {}
	if not R:Act(board, s, action, ev) then
		Bd:Bump(action)
		self:StopWalk()
		return false
	end
	Bd.ver = (Bd.ver or 0) + 1
	undo[#undo + 1] = #moves
	if #undo > 2000 then table.remove(undo, 1) end
	moves = moves .. action
	if #moves % CHECK_EVERY == 0 then checkpoints[#checkpoints + 1] = { moves = moves, snap = R:Copy(s) } end
	evBuf = ev
	Bd:Play(snap, s, ev)
	UpdateHUD(ev)
	SaveRun()
	-- barks: what the party thinks of that turn
	local awakeNear, awake = 0, 0
	for _, m in ipairs(s.mobs) do
		if m.alive and m.awake then
			awake = awake + 1
			if R.Adjacent(m.x, m.y, s.tx, s.ty) then awakeNear = awakeNear + 1 end
		end
	end
	local nosight = false
	for _, e in ipairs(ev) do
		if e[1] == "nosight" then nosight = true end
		if e[1] == "wake" or e[1] == "hit" or e[1] == "cast" or e[1] == "caststart" then self:StopWalk() end
	end
	if nosight and Bd.hadSight == false and s.pips < R.MAX_PIPS then
		if bark.kind ~= "nosight" then Au:Play("healer_los_warning") end
		Bark("nosight")
	elseif awake >= 3 then Bark("big")
	elseif awakeNear >= 2 then Bark("two")
	elseif s.pips <= 2 and not s.over then Bark("low") end
	return true
end

function G:TurnDone()
	if not s then return end
	if s.over then
		self:StopWalk()
		self:ShowResult()
		return
	end
	if walkN > 0 then
		local a = walk[1]
		table.remove(walk, 1)
		walkN = walkN - 1
		self:Do(a)
	end
end

function G:ShowResult()
	local res = screens.results
	if s.over == "clear" then
		local medal, newBest, prev, lbId
		if G.daily then
			medal, newBest, prev = P.Daily:Finish(G.daily, s, moves, board)
			lbId = P.Daily.BOARD_PREFIX .. G.daily
		else
			medal, newBest, prev = Pr:Finish(board.id, s, moves)
			lbId = board.id
		end
		P.char.resume = nil
		if newBest then P.Leaderboard:Record(lbId, s.steps, moves) end
		-- what this clear earned is worked out over the next few frames, then added to the screen
		G:ShowAwards(nil, nil)
		P.Awards:OnClearAsync(board, moves, G.daily, function(newAch, newSkins)
			if G.screen == "results" then G:ShowAwards(newAch, newSkins) end
		end)
		res.title:SetTitle("Room Cleared!")
		A:Sprite(res.art, "results_clear")
		local ms = MedalSprite(medal, true)
		if ms then A:Sprite(res.medal, ms) res.medal:Show() else res.medal:Hide() end
		res.line1:SetText(("%d steps   (par %d, gold %d)"):format(s.steps, board.par or 0, board.gold or 0))
		local l2
		if medal == 3 then l2 = "Gold! There is no cleaner pull."
		elseif medal == 2 then l2 = ("Silver. Gold takes %d steps: there's a tighter pull."):format(board.gold or 0)
		else l2 = ("Bronze. Par is %d: you can save %d steps."):format(board.par or 0, s.steps - (board.par or 0)) end
		if newBest and prev then l2 = l2 .. ("\nNew best! (was %d)"):format(prev) end
		res.line2:SetText(l2)
		local nxt = not G.daily and Pr:Next(board.id) or nil
		res.a:SetLabel(nxt and "Next Room" or (G.daily and "Menu" or "Rooms"))
		res.a.nextId = nxt
		res.a.toMenu = G.daily and true or nil
		res.a.mode = "next"
		Au:Play(("medal_award_%02d"):format(medal))
		Bark(medal == 3 and "gold" or "clear", true)
	else
		res.title:SetTitle("Wipe!")
		A:Sprite(res.art, "results_wipe")
		res.medal:Hide()
		res.line1:SetText(("The party went down on step %d."):format(s.steps))
		res.line2:SetText("Undo goes back one turn: find where the pull went wrong.")
		res.a:SetLabel("Undo")
		res.a.mode = "undo"
		G:ShowAwards(nil, nil)
		Bark("wipe", true)
	end
	self:Screen("results")
end

-- the results screen's line of what a clear earned (badges for achievements, words for shields)
function G:ShowAwards(newAch, newSkins)
	local res = screens.results
	local words = {}
	for _, t in ipairs(res.badges) do t:Hide() end
	local nb = 0
	for _, a in ipairs(newAch or {}) do
		words[#words + 1] = a.name
		if nb < #res.badges then nb = nb + 1 A:Sprite(res.badges[nb], a.badge) end
	end
	local line = {}
	if #words > 0 then line[#line + 1] = "Achievement: " .. table.concat(words, ", ") end
	for _, k in ipairs(newSkins or {}) do line[#line + 1] = "New shield: " .. k.name end
	res.awards:SetText(table.concat(line, "\n"))
	for i = 1, nb do
		local t = res.badges[i]
		t:ClearAllPoints()
		t:SetPoint("TOP", res.awards, "BOTTOM", (i - (nb + 1) / 2) * 58, -4)
		t:Show()
	end
	if #line > 0 then Au:Play("ui_achievement") end
end

function G:ResultA()
	local a = screens.results.a
	if a.mode == "undo" then
		self:Screen(nil)
		self:Undo()
	elseif a.nextId then
		self:Start(a.nextId)
	elseif a.toMenu then
		self:Screen("menu")
	else
		self:Screen("rooms")
	end
end

-- put the state back to "these moves from the start": from the nearest checkpoint, replaying the rest
function G:Rebuild(target)
	local cp
	for i = #checkpoints, 1, -1 do
		local c = checkpoints[i]
		if #c.moves <= #target and target:sub(1, #c.moves) == c.moves then cp = c break end
	end
	local from = 0
	if cp then
		R:Restore(s, cp.snap)
		from = #cp.moves
	else
		R:Restore(s, R:New(board))
	end
	for i = from + 1, #target do
		if s.over or not R:Act(board, s, target:sub(i, i)) then break end
	end
end

function G:Undo()
	if not s or #undo == 0 or InCombat() then Au:Play("ui_error") return end
	if Bd:Busy() then Bd:Finish() end
	self:StopWalk()
	local u = table.remove(undo)
	moves = type(u) == "number" and moves:sub(1, u) or u
	G:Rebuild(moves)
	if self.screen == "results" then self:Screen(nil) end
	Bd.hadSight = nil
	Bd:Sync(s)
	Bd:Rewind()
	UpdateHUD()
	SaveRun()
end

function G:Restart()
	if not board or InCombat() then return end
	if Bd:Busy() then Bd:Finish() end
	self:StopWalk()
	if s and (#moves > 0) then undo[#undo + 1] = moves end
	R:Restore(s, R:New(board))
	moves = ""
	Bd.hadSight = nil
	Bd:Sync(s)
	Bd:Rewind()
	Au:Play("restart")
	UpdateHUD()
	SaveRun()
	self:Screen(nil)
end

function G:Hint()
	if not s or s.over or self.screen then return end
	local sol = board.solution
	if sol and moves == sol:sub(1, #moves) and #moves < #sol then
		Bd:Hint(sol:sub(#moves + 1, #moves + 1))
		Bark("hint", true)
	else
		Bark("lost", true)
	end
end

-- ------------------------------------------------------------------ walking (click a tile)
local prevStep, bfsQ, pathBuf, coordBuf, occ = {}, {}, {}, {}, {}
-- one walking field from the tank per state (Bd.ver), read back for every hovered tile
local fieldVer, fieldStart
local function Field()
	local w, h = board.w, board.h
	local start = (s.ty - 1) * w + s.tx
	if fieldVer == Bd.ver and fieldStart == start then return start end
	fieldVer, fieldStart = Bd.ver, start
	for i = 1, w * h do prevStep[i] = nil occ[i] = nil end
	for _, m in ipairs(s.mobs) do
		if m.alive then occ[(m.y - 1) * w + m.x] = true end
	end
	prevStep[start] = 0
	local head, tail = 1, 1
	bfsQ[1] = start
	local tile, canEnter, ORDER, DIRS = board.tile, R.TankCanEnter, R.ORDER, R.DIRS
	while head <= tail do
		local i = bfsQ[head]
		head = head + 1
		local x, y = (i - 1) % w + 1, floor((i - 1) / w) + 1
		for k = 1, 4 do
			local o = DIRS[ORDER[k]]
			local nx, ny = x + o[1], y + o[2]
			if nx >= 1 and ny >= 1 and nx <= w and ny <= h then
				local j = (ny - 1) * w + nx
				if prevStep[j] == nil and not occ[j] and canEnter(tile[j]) then
					prevStep[j] = i
					tail = tail + 1
					bfsQ[tail] = j
				end
			end
		end
	end
	return start
end

local function PathTo(tx, ty)
	if not s then return nil end
	local w = board.w
	local start = Field()
	local goal = (ty - 1) * w + tx
	if prevStep[goal] == nil or goal == start then return nil end
	-- into one reused buffer, start to goal (read it before the next PathTo)
	local n, i = 0, goal
	while i ~= start do n = n + 1 i = prevStep[i] end
	for k = #pathBuf, n + 1, -1 do pathBuf[k] = nil end
	i = goal
	for k = n, 1, -1 do pathBuf[k] = i i = prevStep[i] end
	return pathBuf
end

function G:Hover(x, y)
	Bd:ClearHover(false, true)          -- the dots stay where the new path still has them
	if not x or not s or s.over or self.screen then Bd.HideDots() return end
	for i, m in ipairs(s.mobs) do
		if m.alive and m.x == x and m.y == y then Bd.HideDots() Bd:Highlight(i) return end
	end
	local path = PathTo(x, y)
	if not path then Bd.HideDots() return end
	local n = min(#path, 48)
	for k = 1, n do
		local i = path[k]
		coordBuf[k * 2 - 1] = (i - 1) % board.w + 1
		coordBuf[k * 2] = floor((i - 1) / board.w) + 1
	end
	Bd:Preview(coordBuf, nil, n * 2)
end

function G:Click(button)
	if self.screen or not s or s.over then return end
	if button == "RightButton" then self:StopWalk() return end
	local x, y = Bd:TileAtCursor()
	if not x then return end
	local path = PathTo(x, y)
	if not path then Au:Play("ui_error") return end
	self:StopWalk()
	local cx, cy = s.tx, s.ty
	for _, i in ipairs(path) do
		local nx, ny = (i - 1) % board.w + 1, floor((i - 1) / board.w) + 1
		local d = (nx > cx and "E") or (nx < cx and "W") or (ny > cy and "S") or "N"
		walkN = walkN + 1
		walk[walkN] = d
		cx, cy = nx, ny
	end
	Bd:ClearHover()
	local a = walk[1]
	table.remove(walk, 1)
	walkN = walkN - 1
	self:Do(a)
end

function G:StopWalk()
	wipe(walk)
	walkN = 0
end

-- ------------------------------------------------------------------ keyboard
local KEYS = { W = "N", UP = "N", S = "S", DOWN = "S", A = "W", LEFT = "W", D = "E", RIGHT = "E", SPACE = "." }

function G:Key(key)
	-- modified keys belong to the player's own bindings
	if IsModifierKeyDown and IsModifierKeyDown() then return false end
	if key == "ESCAPE" then
		if self.screen == "menu" and s and not s.over then self:Screen(nil)
		elseif self.screen == "paused" then return true
		elseif self.screen then self:Screen(s and not s.over and nil or "menu") if not s then self:Close() end
		else self:Screen("menu") end
		return true
	end
	if self.screen then
		if self.screen == "results" and (key == "ENTER" or key == "SPACE") then self:ResultA() return true end
		if key == "R" and self.screen == "results" then self:Restart() return true end
		return false
	end
	local a = KEYS[key]
	if a then
		self:StopWalk()
		self:Do(a)
		return true
	end
	if key == "Z" or key == "BACKSPACE" then self:Undo() return true end
	if key == "R" then self:Restart() return true end
	if key == "H" then self:Hint() return true end
	return false
end

function G:Keyboard(on)
	if not W then return end
	if InCombat() then on = false end
	W:EnableKeyboard(on and true or false)
end

-- ------------------------------------------------------------------ the driver
local function OnError(err)
	P:RecordError("game loop", err)
	return err
end

local debugprofilestop = debugprofilestop
local stepDt = 0
local function Step() Bd:Update(stepDt) end      -- made once: the frame loop allocates nothing
local function Drive(_, elapsed)
	if elapsed > 0.1 then elapsed = 0.1 end   -- a hitch (alt-tab, loading) never jumps the animations
	local t0 = debugprofilestop and debugprofilestop()
	stepDt = elapsed
	Bd.tag = nil
	local ok = xpcall(Step, OnError)
	if not ok then
		W:SetScript("OnUpdate", nil)
		P:Print("something went wrong drawing the board, so it stopped. /bodypull debug shows details; reopening restarts it.")
		return
	end
	if bark.t > 0 then
		bark.t = bark.t - elapsed
		if bark.t <= 0 then hud.bark:Hide() bark.kind = nil end
	end
	if P:Setting("nudge") then
		G.played = (G.played or 0) + elapsed
		if G.played >= 1200 and not G.nudged then G.nudged = true Bark("nudge", true) end
	end
	if t0 then
		local ms = debugprofilestop() - t0
		perf.n = perf.n + 1
		perf.sum = perf.sum + ms
		local tag = Bd.tag or "animation"
		if ms > perf.max then perf.max = ms perf.worstTag = tag end
		if ms > 0.5 then
			perf.over = perf.over + 1
			perf.tags[tag] = (perf.tags[tag] or 0) + 1
		end
	end
end

function G:Shown()
	self:FitScale()
	W:SetScript("OnUpdate", Drive)
	self:Keyboard(true)
	P:Listen("PLAYER_REGEN_DISABLED")
	if self.screen then
		self:Screen(self.screen)
	elseif board then
		Au:Music("music_" .. (board.delve or "candlewick"))
	end
end

function G:Hidden()
	W:SetScript("OnUpdate", nil)       -- closed costs nothing
	self:StopWalk()
	if Bd:Busy() then Bd:Finish() end
	UI:HideTip()
	Au:StopMusic()
	Au:Cancel()
	if not self.combatHidden then P:Off("PLAYER_REGEN_DISABLED") end
	A:Trim()                           -- the unpacked sprite records come back on the next draw
end

-- ------------------------------------------------------------------ open / close
function G:FitScale()
	if not W then return end
	local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
	local size = tonumber(P:Setting("size")) or 0.9
	local sc = min(uw / WIN_W, uh / WIN_H) * max(0.5, min(1, size))
	W:SetScale(max(0.35, min(1.6, sc)))
end

function G:Open()
	if InCombat() then
		P:Print("opens after combat.")
		return
	end
	if not P.char then return end
	if not W then Build() end
	if not board then
		local r = P.char.resume
		local today = P.Daily:Today()
		local daily = type(r) == "table" and r.daily
		if type(r) == "table" and Pr:Room(r.id) and ((daily and daily == today and r.id == P.Daily:RoomId())
			or (not daily and Pr:Unlocked(r.id))) then
			self:Start(r.id, r.moves, daily or nil)
			if s and not s.over then self:Screen(nil) end
		else
			local first = Pr:Rooms("candlewick")[1]
			self:Start(first.id)
			self:Screen("menu")
		end
		-- the very first time: a welcome, and a choice of window size
		if P.db and not P.db.welcomed and (screens.welcome or G.lazy.welcome) then self:Screen("welcome") end
	end
	W:Show()
	Au:Play("ui_menu_open")
end

function G:Close()
	if not W or not W:IsShown() then return end
	Au:Play("ui_menu_close")
	W:Hide()
end

function G:Toggle()
	if W and W:IsShown() then self:Close() else self:Open() end
end

function G:IsOpen() return W ~= nil and W:IsShown() end

-- forget the run on screen (after /bodypull reset): the next open starts from the menu
function G:Forget()
	if W and W:IsShown() then W:Hide() end
	board, s = nil, nil
	G.board, G.s = nil, nil
	wipe(undo)
	wipe(checkpoints)
	moves = ""
end

-- ------------------------------------------------------------------ combat: step aside at once
P:On("PLAYER_REGEN_DISABLED", function()
	if not W or not W:IsShown() then return end
	G.combatHidden = true
	G:StopWalk()
	if Bd:Busy() then Bd:Finish() end
	W:EnableKeyboard(false)
	G:Screen("paused")
	screens.paused.text:SetText("You're in combat. The run is frozen exactly as it was.\nWhen the fight is over, click Resume.")
	screens.paused.resume:SetEnabled(false)
	W:Hide()
	P:Listen("PLAYER_REGEN_ENABLED")
end)
P:Off("PLAYER_REGEN_DISABLED")

P:On("PLAYER_REGEN_ENABLED", function()
	P:Off("PLAYER_REGEN_ENABLED")
	if not G.combatHidden then return end
	G.combatHidden = false
	if not W then return end
	screens.paused.text:SetText("The fight is over. Your run is waiting.")
	screens.paused.resume:SetEnabled(true)
	W:Show()
	G:Keyboard(false)            -- the keyboard comes back with the Resume click, not before
	G:Screen("paused")
end)
P:Off("PLAYER_REGEN_ENABLED")

P:On("DISPLAY_SIZE_CHANGED", function() G:FitScale() end)
P:On("UI_SCALE_CHANGED", function() G:FitScale() end)

-- ------------------------------------------------------------------ perf / debug
function G:Perf()
	local avg = perf.n > 0 and perf.sum / perf.n or 0
	local mem
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		mem = GetAddOnMemoryUsage(P.name)
	end
	P:Print("frame time %.3f ms average, %.3f ms worst over %d frames, %d frame(s) over the 0.5 ms budget; %s; memory %s KB.",
		avg, perf.max, perf.n, perf.over, (W and W:IsShown()) and "window open" or "window closed: 0 ms, no OnUpdate",
		mem and ("%.0f"):format(mem) or "?")
	if perf.n > 0 then
		local parts = {}
		for tag, n in pairs(perf.tags) do parts[#parts + 1] = ("%s %d"):format(tag, n) end
		P:Print("worst frame: %s. Over budget: %s.", perf.worstTag or "-", #parts > 0 and table.concat(parts, ", ") or "none")
	end
	perf.n, perf.sum, perf.max, perf.over, perf.worstTag = 0, 0, 0, 0, nil
	wipe(perf.tags)
end
