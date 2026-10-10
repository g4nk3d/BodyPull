--[[ Body Pull - UI/Board.lua
	Draws a room and plays each turn's events: tiles, the party, the mobs, rings, chains, sight lines,
	path preview and effects. It never changes game state: it shows what Game/Rules.lua did.

	  Bd:Build(parent, w, h)     once: the board area (all textures pooled here; nothing is created later)
	  Bd:Load(board, s)          draw a room and snap everything to state s
	  Bd:Sync(s)                 snap every actor to state s (undo, restart, end of a turn's playback)
	  Bd:Play(prev, s, ev)       animate one turn: prev = the state before, s = after, ev = its events
	  Bd:Finish()                fast-forward any playback (a key pressed mid-animation)
	  Bd:Busy()                  playback still running
	  Bd:Bump(dir)               the tank bumps a wall (no turn)
	  Bd:Update(dt)              the driver (called by the window's single OnUpdate)
	  Bd:TileAtCursor()          the tile under the mouse, or nil
	  Bd:Preview(path)           footstep dots (and danger rings) for a click-to-walk path
	  Bd:Highlight(x, y)         hover: a mob's ring, chain and tooltip
	  Bd:Hint(dir)               the lantern hint: an arrow of dots for the suggested next move
	  Bd.onDone                  called when a turn's playback ends (the window reads it)

	Coordinates: tiles are 1-based (x right, y down). One tile is T display pixels; the art's atlas
	scale is 64 px per tile, so a sprite of n atlas px shows at n * T / 64. ]]

local _, ns = ...
local P = ns.P
local Bd = P:Module("Board")
local A, Au, UI = P.Assets, P.Audio, P.UI
local R = ns.Rules
local TT = R.T

local floor, max, min, abs, sqrt, atan2 = math.floor, math.max, math.min, math.abs, math.sqrt, math.atan2
local GetCursorPosition = GetCursorPosition

local MAXW, MAXH = 15, 11      -- the largest room the pools are made for (Rules refuses bigger)
local MAXT = MAXW * MAXH
local T = 48          -- tile size in display px (set per room to fit the area)
local K = T / 64      -- display px per atlas px

local area            -- the board's region of the window
local bf, of, af, xf  -- board (tiles), overlay (rings, dots), actors, effects frames
local board, state    -- the room on screen and the state last synced

-- pools, all made in Build
local floorTex, wallTex, decoTex = {}, {}, {}
local propTex = {}            -- pillars and low props (drawn in the actor frame for depth)
local HideDots                -- the hover dots' tidy-up (defined with the preview, below)
local nWall, nProp = 0, 0     -- walls and props are pooled by count (made as a room first needs them)
local campTex, entTex, poolTex, tintTex, partyTex, partyGlow
local ringTex, dangerTex = nil, {}
local chainTex, sightTex, dotTex = {}, {}, {}
local fx = {}                 -- one-shot effects
local tank, party, mobs = nil, {}, {}
local castBars = {}
local zzz = {}
local hoverAnchor
local terrain, terrainN, terrainClock, terrainFrame = {}, 0, 0, 0   -- water / lava tiles and their loop
-- a closed sarcophagus drawn like a one-frame animation on the opening sequence's canvas
local COFFIN
local function Coffin()
	if not COFFIN then
		local op = A:Anim("sarcophagus_ambusher_opening")
		COFFIN = { fps = 1, loop = true, w = op.w, h = op.h, px = op.px, py = op.py, "sarcophagus_ambusher_closed" }
	end
	return COFFIN
end
local TERRAIN_ANIM = { [TT.WATER] = "blackbrine_terrain_loop", [TT.LAVA] = "emberdeep_terrain_loop" }
local N_CHAIN, N_SIGHT, N_DOT, N_FX, N_DANGER, N_MOBS = 40, 24, 48, 24, 8, 16

-- ------------------------------------------------------------------ helpers
local function TileXY(x, y)          -- tile centre, relative to the board's top-left (y up negative)
	return (x - 0.5) * T, -(y - 0.5) * T
end

local function SubFor(y)             -- draw order: lower rows in front
	return max(-8, min(7, floor(y + 0.5) - 5))
end

local function Place(t, cx, cy, w, h)  -- centre a region on board coordinates
	t:ClearAllPoints()
	t:SetPoint("CENTER", bf, "TOPLEFT", cx, cy)
	t:SetSize(w, h)
end

-- ------------------------------------------------------------------ actors
--[[ an actor: one texture showing an animation, positioned by its foot pivot on a tile.
	act.art = animation prefix ("kobold_digger"), act.anim = current animation table,
	act.loop / act.next = what plays after a one-shot, act.t = time in the animation ]]
local function NewActor(layerFrame)
	local a = { tex = layerFrame:CreateTexture(nil, "ARTWORK"), t = 0, frame = 0, x = 1, y = 1, fx = 1, fy = 1,
		tx = 1, ty = 1, mt = 0, md = 0, delay = 0, scale = 1 }
	a.tex:Hide()
	return a
end

local function ActorPos(a)
	local an = a.anim
	if not an then return end
	local k = K * a.scale
	local w, h = an.w * k, an.h * k
	local cx, cy = TileXY(a.x, a.y)
	cy = cy - T * 0.28                 -- feet a little below the tile centre: miniatures on a board
	local px, py = an.px * k, an.py * k
	if a.flip then px = w - px end
	local l, t = cx - px, cy + py
	-- unchanged since the last call (most actors at the end of a turn): no anchor work at all
	if a.pl == l and a.pt == t and a.pw == w and a.ph == h then return end
	a.pl, a.pt, a.pw, a.ph = l, t, w, h
	a.tex:ClearAllPoints()
	a.tex:SetPoint("TOPLEFT", bf, "TOPLEFT", l, t)
	a.tex:SetSize(w, h)
	a.tex:SetDrawLayer("ARTWORK", SubFor(a.y))
end

local function SetAnimTable(a, an, loop, nextName)
	if a.anim == an and loop and a.loop then return true end
	a.anim, a.loop, a.next, a.t, a.frame = an, loop, nextName, 0, 0
	A:Sprite(a.tex, an[1], a.flip)
	a.tex:Show()
	ActorPos(a)
	return true
end

-- an actor's animation by state name ("idle", "attack"), looked up once per art and state: building the
-- "<art>_<state>" name every turn would leave garbage behind (and garbage collection shows up as frame spikes)
local animNames = {}
local function ActorAnim(a, name)
	local art = a.art
	local byArt = animNames[art]
	if not byArt then byArt = {} animNames[art] = byArt end
	local full = byArt[name]
	if not full then full = art .. "_" .. name byArt[name] = full end
	return A:Anim(full)
end

local function SetAnim(a, name, loop, nextName)
	local an = ActorAnim(a, name)
	if not an then return false end
	if a.anim == an and loop and a.loop then return true end
	a.anim, a.loop, a.next, a.t, a.frame = an, loop, nextName, 0, 0
	A:Sprite(a.tex, an[1], a.flip)
	a.tex:Show()
	ActorPos(a)
	return true
end

local function Face(a, towardX)
	local flip = towardX < a.x - 0.01
	if towardX > a.x - 0.01 and towardX < a.x + 0.01 then flip = a.flip end
	if flip ~= a.flip then
		a.flip = flip
		if a.anim then
			local i = a.frame > 0 and a.frame or 1
			A:Frame(a.tex, a.anim, i, flip)
			ActorPos(a)
		end
	end
end

local function MoveActor(a, fromX, fromY, toX, toY, dur, delay)
	a.fx, a.fy, a.tx, a.ty = fromX, fromY, toX, toY
	a.md, a.mt, a.delay = dur, 0, delay or 0
	a.x, a.y = fromX, fromY
	ActorPos(a)
end

local function UpdateActor(a, dt)
	if not a.anim then return end
	-- movement
	if a.md > 0 then
		if a.delay > 0 then
			a.delay = a.delay - dt
		else
			a.mt = a.mt + dt
			local f = min(1, a.mt / a.md)
			f = f * f * (3 - 2 * f)
			a.x = a.fx + (a.tx - a.fx) * f
			a.y = a.fy + (a.ty - a.fy) * f
			if a.mt >= a.md then a.md = 0 a.x, a.y = a.tx, a.ty end
			ActorPos(a)
		end
	end
	-- animation
	a.t = a.t + dt
	local an = a.anim
	local n = #an
	local i = floor(a.t * an.fps)
	if a.loop then
		i = i % n + 1
	elseif i >= n then
		if a.next then
			local nx = a.next
			a.next = nil
			if not SetAnim(a, nx, true) then i = n end
			return
		end
		i = n
		if a.hideAtEnd then a.tex:Hide() a.anim = nil return end
	else
		i = i + 1
	end
	if i ~= a.frame then
		a.frame = i
		A:Frame(a.tex, an, i, a.flip)
	end
end

-- ------------------------------------------------------------------ effects
local function FX(name, x, y, size, opts)
	local an = A:Anim(name)
	if not an then return end
	local e
	for i = 1, N_FX do
		if not fx[i].an then e = fx[i] break end
	end
	if not e then e = fx[1] end              -- the oldest-looking slot: never more than N_FX at once
	e.an, e.t, e.frame, e.delay = an, 0, 0, opts and opts.delay or 0
	e.loop = opts and opts.loop
	e.follow = opts and opts.follow
	e.x, e.y, e.size, e.rise = x, y, size or T * 1.4, opts and opts.rise or 0
	A:Sprite(e.tex, an[1])
	e.tex:SetBlendMode(opts and opts.add and "ADD" or "BLEND")
	e.tex:Hide()
	return e
end

local function UpdateFX(e, dt)
	if e.delay > 0 then
		e.delay = e.delay - dt
		return
	end
	if not e.tex:IsShown() then e.tex:Show() end
	e.t = e.t + dt
	local an = e.an
	local n = #an
	local i = floor(e.t * an.fps)
	if e.loop then
		i = i % n + 1
	elseif i >= n then
		e.an = nil
		e.tex:Hide()
		return
	else
		i = i + 1
	end
	local x, y = e.x, e.y
	if e.follow then x, y = e.follow.x, e.follow.y end
	local cx, cy = TileXY(x, y)
	Place(e.tex, cx, cy + e.rise, e.size, e.size)
	if i ~= e.frame then
		e.frame = i
		A:Frame(e.tex, an, i)
	end
end

local function StopFX(e)
	if e then e.an = nil e.tex:Hide() end
end

-- ------------------------------------------------------------------ build
function Bd:Build(parent, w, h)
	area = CreateFrame("Frame", nil, parent)
	area:SetSize(w, h)
	self.area = area
	bf = CreateFrame("Frame", nil, area)
	bf:SetSize(w, h)
	bf:SetPoint("CENTER")
	bf:EnableMouse(true)
	self.frame = bf
	of = CreateFrame("Frame", nil, bf)
	of:SetAllPoints()
	of:SetFrameLevel(bf:GetFrameLevel() + 2)
	af = CreateFrame("Frame", nil, bf)
	af:SetAllPoints()
	af:SetFrameLevel(bf:GetFrameLevel() + 4)
	xf = CreateFrame("Frame", nil, bf)
	xf:SetAllPoints()
	xf:SetFrameLevel(bf:GetFrameLevel() + 6)

	for i = 1, MAXT do
		floorTex[i] = bf:CreateTexture(nil, "BACKGROUND", nil, -8)
		floorTex[i]:Hide()
	end
	for i = 1, 24 do
		decoTex[i] = bf:CreateTexture(nil, "BORDER", nil, 2)
		decoTex[i]:Hide()
	end
	campTex = bf:CreateTexture(nil, "BACKGROUND", nil, -6)
	entTex = bf:CreateTexture(nil, "BACKGROUND", nil, -6)
	poolTex = of:CreateTexture(nil, "BACKGROUND", nil, 0)
	A:Sprite(poolTex, "lantern_pool")
	poolTex:SetBlendMode("ADD")
	poolTex:SetVertexColor(1, 0.78, 0.45, 0.55)
	-- the party ring: where Kesk and Wyn can hit (always shown, flares when they strike)
	partyTex = of:CreateTexture(nil, "ARTWORK", nil, 0)
	A:Sprite(partyTex, "aggro_ring")
	partyTex:SetVertexColor(0.55, 0.95, 0.55, 0.6)
	-- a soft green wash under the dashes, so the ring reads as an area, not loose marks
	partyGlow = of:CreateTexture(nil, "BACKGROUND", nil, 1)
	A:Sprite(partyGlow, "danger_ring")
	partyGlow:SetBlendMode("ADD")
	partyGlow:SetVertexColor(0.35, 0.9, 0.4, 0.35)
	ringTex = of:CreateTexture(nil, "ARTWORK", nil, 2)
	A:Sprite(ringTex, "aggro_ring")
	ringTex:Hide()
	for i = 1, N_DANGER do
		local t = of:CreateTexture(nil, "ARTWORK", nil, 1)
		A:Sprite(t, "danger_ring")
		t:SetBlendMode("ADD")
		t:Hide()
		dangerTex[i] = t
	end
	for i = 1, N_CHAIN do
		local t = of:CreateTexture(nil, "ARTWORK", nil, 3)
		A:Sprite(t, "pack_chain")
		t:Hide()
		chainTex[i] = t
	end
	for i = 1, N_SIGHT do
		local t = of:CreateTexture(nil, "ARTWORK", nil, 4)
		A:Sprite(t, "sight_line")
		t:SetVertexColor(1, 0.86, 0.5, 0.8)
		t:Hide()
		sightTex[i] = t
	end
	for i = 1, N_DOT do
		local t = of:CreateTexture(nil, "ARTWORK", nil, 5)
		A:Sprite(t, "path_dot")
		t:Hide()
		dotTex[i] = t
	end
	tintTex = xf:CreateTexture(nil, "OVERLAY", nil, 7)
	tintTex:SetAllPoints(bf)
	tintTex:SetColorTexture(161 / 255, 114 / 255, 66 / 255, 0.25)
	tintTex:Hide()
	for i = 1, N_FX do
		fx[i] = { tex = xf:CreateTexture(nil, "OVERLAY", nil, 0), t = 0 }
		fx[i].tex:Hide()
	end
	for i = 1, N_MOBS do
		local cb = CreateFrame("Frame", nil, xf)
		cb:SetSize(48, 9)
		cb.frame = cb:CreateTexture(nil, "OVERLAY", nil, 2)
		cb.frame:SetAllPoints()
		A:Sprite(cb.frame, "cast_bar_frame")
		cb.fill = cb:CreateTexture(nil, "OVERLAY", nil, 1)
		A:Sprite(cb.fill, "cast_bar_fill")
		cb.fill:SetPoint("LEFT")
		cb.fill:SetHeight(9)
		cb:Hide()
		castBars[i] = cb
		zzz[i] = { tex = xf:CreateTexture(nil, "OVERLAY", nil, 1), t = 0 }
		zzz[i].tex:Hide()
		mobs[i] = NewActor(af)
	end
	tank = NewActor(af)
	tank.art = "tank"
	for i, art in ipairs({ "aldous", "kesk", "wyn" }) do
		party[i] = NewActor(af)
		party[i].art = art
		party[i].scale = 0.9
	end
	hoverAnchor = CreateFrame("Frame", nil, xf)
	hoverAnchor:SetSize(1, 1)

	bf:SetScript("OnEnter", function() Bd.mouseIn = true end)
	bf:SetScript("OnLeave", function() Bd.mouseIn = false Bd:ClearHover() end)
end

-- ------------------------------------------------------------------ room
local DECOR = { "decor_lantern", "decor_candle", "decor_torch", "decor_chain" }

local function IsWall(b, x, y) return R.Tile(b, x, y) == TT.WALL end

function Bd:Load(b, s)
	HideDots()
	board = b
	local delve = b.delve or "candlewick"
	T = floor(min(area:GetWidth() / b.w, area:GetHeight() / b.h))
	T = max(24, min(64, T))
	K = T / 64
	bf:SetSize(b.w * T, b.h * T)
	for i = 1, MAXT do floorTex[i]:Hide() end
	for i = 1, #wallTex do wallTex[i]:Hide() end
	for i = 1, #propTex do propTex[i]:Hide() end
	nWall, nProp = 0, 0
	for i = 1, #decoTex do decoTex[i]:Hide() end
	local nd = 0
	terrainN = 0
	for y = 1, b.h do
		for x = 1, b.w do
			local i = (y - 1) * b.w + x
			local t = b.tile[i]
			local cx, cy = TileXY(x, y)
			if t ~= TT.VOID then
				local f = floorTex[i]
				A:Sprite(f, ("%s_floor_%02d"):format(delve, (x * 7 + y * 13) % 4 + 1))
				-- a hair larger than the tile, so no seam shows at fractional UI scales
				Place(f, cx, cy, T + 0.6, T + 0.6)
				-- under a wall the floor is dark rock: walls read as solid blocks, not thin rails
				if t == TT.WALL then f:SetVertexColor(0.3, 0.27, 0.25) else f:SetVertexColor(1, 1, 1) end
				-- the forge floor is painted with glowing cracks: quieted down so the real lava stands out
				local calm = delve == "emberdeep" and t == TT.FLOOR
				if f.SetDesaturation then f:SetDesaturation(calm and 0.65 or 0) else f:SetDesaturated(calm) end
				if calm then f:SetVertexColor(0.62, 0.58, 0.55) end
				local ta = TERRAIN_ANIM[t] and A:Anim(TERRAIN_ANIM[t])
				if ta then
					A:Sprite(f, ta[1])
					terrainN = terrainN + 1
					local e = terrain[terrainN] or {}
					terrain[terrainN] = e
					e.tex, e.an = f, ta
				end
				f:Show()
			end
			if t == TT.WALL then
				local mask = (IsWall(b, x, y - 1) and 1 or 0) + (IsWall(b, x + 1, y) and 2 or 0)
					+ (IsWall(b, x, y + 1) and 4 or 0) + (IsWall(b, x - 1, y) and 8 or 0)
				nWall = nWall + 1
				local wt = wallTex[nWall]
				if not wt then
					wt = bf:CreateTexture(nil, "BORDER", nil, 0)
					wallTex[nWall] = wt
				end
				A:Sprite(wt, ("%s_wall_%02d"):format(delve, mask))
				Place(wt, cx, cy, T, T)
				wt:Show()
				-- wall-top decorations on straight east-west runs, spaced out, always the same per room
				if mask == 10 and (x * 3 + y) % 5 == 0 and nd < #decoTex then
					nd = nd + 1
					local d = decoTex[nd]
					A:Sprite(d, delve .. "_" .. DECOR[(x + y) % 4 + 1])
					Place(d, cx, cy + T * 0.18, T * 0.8, T * 0.8)
					d:Show()
				end
			elseif t == TT.PILLAR or t == TT.PROP then
				nProp = nProp + 1
				local pt = propTex[nProp]
				if not pt then
					pt = af:CreateTexture(nil, "ARTWORK")
					propTex[nProp] = pt
				end
				local name = t == TT.PILLAR and ("%s_pillar_%d"):format(delve, (x + y) % 2 + 1)
					or (delve .. "_" .. (b.prop[i] or "crate"))
				if not A:Has(name) then name = delve .. "_crate" end
				local w, h = A:Size(name)
				A:Sprite(pt, name)
				pt:ClearAllPoints()
				pt:SetPoint("BOTTOM", bf, "TOPLEFT", cx, cy - T * 0.5)
				pt:SetSize(w * K, h * K)
				pt:SetDrawLayer("ARTWORK", SubFor(y))
				pt:Show()
			end
		end
	end
	local ccx, ccy = b.campX * T, -b.campY * T
	A:Sprite(campTex, delve .. "_camp")
	Place(campTex, ccx, ccy, T * 2, T * 2)
	local ex, ey = TileXY(b.sx, b.sy)
	A:Sprite(entTex, delve .. "_entrance")
	Place(entTex, ex, ey, T, T)
	Place(poolTex, ccx, ccy, T * 7, T * 7)
	Place(partyTex, ccx, ccy, R.PARTY_RADIUS * 2 * T, R.PARTY_RADIUS * 2 * T)
	Place(partyGlow, ccx, ccy, R.PARTY_RADIUS * 2 * T, R.PARTY_RADIUS * 2 * T)
	partyTex:SetAlpha(0.6)
	self.partyFlash = nil
	-- the party around the rug's top edge, the tank wherever it starts
	local spots = { { b.campX + 0.15, b.campY - 0.05 }, { b.campX + 1.85, b.campY - 0.05 }, { b.campX + 1, b.campY + 1.55 } }
	for i, a in ipairs(party) do
		a.x, a.y = spots[i][1], spots[i][2]
		a.flip = nil
		SetAnim(a, "idle", true)
	end
	for i = 1, N_MOBS do
		local m = b.mobs[i]
		local a = mobs[i]
		if m then
			a.art = R.KINDS[m.kind].art
			a.scale = 1
		else
			a.anim = nil
			a.tex:Hide()
		end
	end
	self:ClearHover()
	self:Sync(s)
	self:Chains()
end

-- chains between linked sleeping mobs: short links laid along the line between neighbours in a pack
function Bd:Chains()
	local n = 0
	for i = 1, N_CHAIN do chainTex[i]:Hide() end
	if not board or not state then return end
	local groups = {}
	for i, m in ipairs(board.mobs) do
		if m.link and state.mobs[i].alive and not state.mobs[i].awake then
			groups[m.link] = groups[m.link] or {}
			table.insert(groups[m.link], i)
		end
	end
	for _, list in pairs(groups) do
		for j = 2, #list do
			local a, b2 = state.mobs[list[j - 1]], state.mobs[list[j]]
			local ax, ay = TileXY(a.x, a.y)
			local bx, by = TileXY(b2.x, b2.y)
			local dx, dy = bx - ax, by - ay
			local len = sqrt(dx * dx + dy * dy)
			local seg = T * 0.42
			local count = max(1, floor(len / seg))
			local ang = atan2(dy, dx)
			for k = 1, count do
				if n >= N_CHAIN then break end
				n = n + 1
				local t = chainTex[n]
				local f = (k - 0.5) / count
				Place(t, ax + dx * f, ay + dy * f - T * 0.1, seg, seg * 0.5)
				if t.SetRotation then t:SetRotation(ang) end
				t:Show()
			end
		end
	end
end

-- ------------------------------------------------------------------ sync
local function MobIdle(a, m, d)
	local k = R.KINDS[d.kind]
	a.tex:SetDesaturated(false)
	a.tex:SetVertexColor(1, 1, 1)
	if not m.alive then
		a.anim = nil
		a.tex:Hide()
	elseif not m.awake and k.ambush then
		SetAnimTable(a, Coffin(), true)
	elseif not m.awake and d.route then
		SetAnim(a, "idle_awake", true)      -- a patrol is up and walking, just not looking for you yet
	elseif not m.awake then
		SetAnim(a, "asleep", true)
	elseif m.cast > 0 and ActorAnim(a, "cast") then
		SetAnim(a, "cast", true)
	else
		SetAnim(a, "idle_awake", true)
	end
end

function Bd:Sync(s)
	state = s
	self.ver = (self.ver or 0) + 1      -- the state changed: cached hover answers are stale
	if not board then return end
	tank.md = 0
	tank.x, tank.y = s.tx, s.ty
	SetAnim(tank, (s.over == "wipe") and "wipe" or (s.pips <= 2 and "low_health_idle" or "idle"), s.over ~= "wipe")
	ActorPos(tank)
	for i = 1, #board.mobs do
		local m, a = s.mobs[i], mobs[i]
		a.md = 0
		a.x, a.y = m.x, m.y
		a.hideAtEnd = nil
		local d = board.mobs[i]
		MobIdle(a, m, d)
		if a.anim then Face(a, s.tx) ActorPos(a) end
		-- Kolgrim out of sight: stone-still and grey
		if m.alive and m.awake and R.KINDS[d.kind].statue and not R:Sees(board, m.x, m.y, s.tx, s.ty) then
			a.tex:SetDesaturated(true)
			a.tex:SetVertexColor(0.8, 0.8, 0.85)
		end
		local z = zzz[i]
		if m.alive and not m.awake and not d.route and not R.KINDS[d.kind].ambush then
			z.an = A:Anim("zzz_effect")
			z.t = (i * 0.37) % 1
			z.x, z.y = m.x, m.y
			A:Sprite(z.tex, z.an[1])
			z.tex:Show()
		else
			z.an = nil
			z.tex:Hide()
		end
		local cb = castBars[i]
		if m.alive and m.cast > 0 then
			local cx, cy = TileXY(m.x, m.y)
			cb:ClearAllPoints()
			cb:SetPoint("CENTER", bf, "TOPLEFT", cx, cy + T * 1.05)
			cb:SetSize(T * 0.95, T * 0.18)
			local k = R.KINDS[board.mobs[i].kind].cast
			local f = (k.turns - m.cast + 1) / (k.turns + 1)
			cb.fill:SetWidth(max(1, T * 0.95 * f))
			cb.fill:SetHeight(T * 0.18)
			cb:Show()
		else
			cb:Hide()
		end
	end
	for _, a in ipairs(party) do
		if s.over == "wipe" then
			SetAnim(a, "wipe", false)
		elseif s.over ~= "clear" then
			SetAnim(a, "idle", true)
		end
		Face(a, s.tx)
	end
	self:SightLine()
	self:Chains()
	self.busy = false
end

-- the healer's reach: a dotted beam from the healer to the tank while healing is possible
function Bd:SightLine()
	for i = 1, N_SIGHT do sightTex[i]:Hide() end
	if not board or not state or state.over then return end
	if not R:HealerSees(board, state) then return end
	if R:OnCamp(board, state.tx, state.ty) then return end
	local ax, ay = board.hx * T, -board.hy * T
	local bx, by = TileXY(state.tx, state.ty)
	local dx, dy = bx - ax, by - ay
	local len = sqrt(dx * dx + dy * dy)
	local seg = T * 0.5
	local count = min(N_SIGHT, max(1, floor(len / seg)))
	local ang = atan2(dy, dx)
	for k = 1, count do
		local t = sightTex[k]
		local f = (k - 0.5) / count
		Place(t, ax + dx * f, ay + dy * f, seg * 0.9, seg * 0.22)
		if t.SetRotation then t:SetRotation(ang) end
		t:Show()
	end
end

-- ------------------------------------------------------------------ turn playback
local queue = {}      -- { at, kind, i, a } scheduled effects of the current turn (reused records)
local qn, clock = 0, 0
local function At(at, kind, i, a)
	qn = qn + 1
	local q = queue[qn]
	if not q then q = {} queue[qn] = q end
	q.at, q.kind, q.i, q.a, q.done = at, kind, i, a, false
end

local DEATH = { candlewick = "mob_death_candlewick", blackbrine = "mob_death_blackbrine",
	ashveil = "mob_death_ashveil", emberdeep = "mob_death_emberdeep" }
local BOSS = { candlewick = "boss_wake_candlewick", blackbrine = "boss_wake_blackbrine",
	ashveil = "boss_wake_ashveil", emberdeep = "boss_wake_emberdeep" }

local function Run(q)
	local kind, i = q.kind, q.i
	local delve = board.delve or "candlewick"
	if kind == "wake" then
		local a = mobs[i]
		if R.KINDS[board.mobs[i].kind].ambush then
			SetAnimTable(a, A:Anim("sarcophagus_ambusher_opening"), false, "idle_awake")
			Au:Play("sarcophagus_open")
		else
			SetAnim(a, "wake", false, "idle_awake")
		end
		FX("wake_alert_effect", state.mobs[i].x, state.mobs[i].y, T * 0.9, { rise = T * 1.15 })
		zzz[i].an = nil
		zzz[i].tex:Hide()
		if not q.a then Au:Play("mob_wake") end
	elseif kind == "pack" then
		Au:Play("pack_wake")
		local m = state.mobs[i]
		FX("wake_shockwave_effect", m.x, m.y, T * 3, { add = true })
	elseif kind == "boss" then
		Au:Play(BOSS[delve])
		local m = state.mobs[i]
		FX("wake_shockwave_effect", m.x, m.y, T * 4.5, { add = true })
	elseif kind == "dps" then
		partyTex:SetAlpha(1)
		Bd.partyFlash = 0.5
		local who = party[(i % 2 == 0) and 2 or 3]
		if who == party[2] then SetAnim(who, "attack", false, "idle") else SetAnim(who, "cast", false, "idle") end
		SetAnim(mobs[i], "hit", false, "idle_awake")
		FX("hit_spark_effect", state.mobs[i].x, state.mobs[i].y, T * 1.1, { rise = T * 0.4 })
	elseif kind == "kill" then
		local a = mobs[i]
		SetAnim(a, "death", false)
		a.hideAtEnd = true
		castBars[i]:Hide()
		FX("death_poof_effect", state.mobs[i].x, state.mobs[i].y, T * 1.4, { delay = 0.25, rise = T * 0.3 })
		Au:Play(DEATH[delve])
	elseif kind == "hit" then
		SetAnim(mobs[i], "attack", false, "idle_awake")
		local block = q.a == "block"
		SetAnim(tank, block and "block" or "hit", false, state.pips <= 2 and "low_health_idle" or "idle")
		FX(block and "block_flash_effect" or "hit_spark_effect", state.tx, state.ty, T * 1.2, { rise = T * 0.45, add = block })
		Au:Pick("melee_hit", 3)
	elseif kind == "caststart" then
		SetAnim(mobs[i], "cast", true)
		Au:Play("cast_windup_loop")
	elseif kind == "cast" then
		SetAnim(mobs[i], "attack", false, "idle_awake")
		SetAnim(tank, "hit", false, state.pips <= 2 and "low_health_idle" or "idle")
		FX("cast_impact_effect", state.tx, state.ty, T * 1.5, { rise = T * 0.4, add = true })
		Au:Play("cast_land")
	elseif kind == "fizzle" then
		SetAnim(mobs[i], "idle_awake", true)
	elseif kind == "heal" then
		SetAnim(party[1], "heal_cast", false, "idle")
		FX("heal_glow_effect", state.tx, state.ty, T * 1.8, { rise = T * 0.5, add = true })
		Au:Play("heal")
	elseif kind == "nosight" then
		SetAnim(party[1], "worried", false, "idle")
	elseif kind == "wipe" then
		SetAnim(tank, "wipe", false)
		for _, a in ipairs(party) do SetAnim(a, "wipe", false) end
		Au:Play("stinger_wipe")
	elseif kind == "clear" then
		SetAnim(tank, "victory", false, "idle")
		for _, a in ipairs(party) do if not SetAnim(a, "cheer", false, "idle") then SetAnim(a, "idle", true) end end
		FX("room_clear_effect", (board.w + 1) / 2, (board.h + 1) / 2, max(board.w, board.h) * T * 0.75, { add = true })
		Au:Play("stinger_room_clear")
	elseif kind == "step" then
		if R.Tile(board, state.tx, state.ty) == TT.WATER then Au:Play("water_wade") else Au:Pick("footstep", 3) end
	elseif kind == "fear" then
		SetAnim(tank, "hit", false, state.pips <= 2 and "low_health_idle" or "idle")
	elseif kind == "burn" then
		FX("hit_spark_effect", state.tx, state.ty, T * 1.1, { rise = T * 0.2, add = true })
		Au:Play("lava_hiss")
	elseif kind == "patrol" then
		Au:Play("patrol_step")
	elseif kind == "end" then
		Bd:Sync(state)
		if Bd.onDone then P:Safe("turn done", Bd.onDone) end
	end
end

function Bd:Play(prev, s, ev)
	state = s
	qn, clock = 0, 0
	self.busy = true
	self:ClearHover(true)
	-- the tank moves first, the mobs right after
	if prev.tx ~= s.tx or prev.ty ~= s.ty then
		Face(tank, s.tx)
		MoveActor(tank, prev.tx, prev.ty, s.tx, s.ty, 0.13, 0)
		SetAnim(tank, "step", false, s.pips <= 2 and "low_health_idle" or "idle")
		At(0, "step")
	end
	for i = 1, #board.mobs do
		local a, m, pm = mobs[i], s.mobs[i], prev.mobs[i]
		if m.alive and (pm.x ~= m.x or pm.y ~= m.y) then
			Face(a, m.x > pm.x and m.x + 1 or (m.x < pm.x and m.x - 1 or s.tx))
			MoveActor(a, pm.x, pm.y, m.x, m.y, 0.16, 0.1)
		end
	end
	local packWoke = false
	for _, e in ipairs(ev) do if e[1] == "pack" or e[1] == "boss" then packWoke = true end end
	local endAt = 0.32
	local patrolled = false
	local hadSight = self.hadSight
	self.hadSight = true
	for _, e in ipairs(ev) do
		local k = e[1]
		if k == "wake" then At(0.1, "wake", e[2], packWoke)
		elseif k == "pack" then
			local first
			for i, m in ipairs(board.mobs) do if m.link == e[2] then first = first or i end end
			At(0.08, "pack", first)
		elseif k == "boss" then At(0.08, "boss", e[2]) endAt = 0.6
		elseif k == "dps" then At(0.14, "dps", e[2])
		elseif k == "kill" then At(0.26, "kill", e[2]) endAt = max(endAt, 0.55)
		elseif k == "hit" then At(0.22, "hit", e[2], s.pips >= 3 and "block" or "hit")   -- early blows glance off the shield
		elseif k == "caststart" then At(0.2, "caststart", e[2])
		elseif k == "cast" then At(0.24, "cast", e[2])
		elseif k == "fizzle" then At(0.2, "fizzle", e[2])
		elseif k == "fear" then At(0.3, "fear")
		elseif k == "burn" then At(0.3, "burn")
		elseif k == "patrol" and not patrolled then patrolled = true At(0.12, "patrol")
		elseif k == "heal" then At(0.36, "heal") endAt = max(endAt, 0.45)
		elseif k == "nosight" then
			self.hadSight = false
			if hadSight ~= false then At(0.3, "nosight") end
		elseif k == "wipe" then At(0.36, "wipe") endAt = 1.5
		elseif k == "clear" then At(0.45, "clear") endAt = 1.7
		end
	end
	At(endAt, "end")
end

function Bd:Busy() return self.busy end

function Bd:Finish()
	if not self.busy then return end
	for j = 1, qn do
		local q = queue[j]
		if not q.done and q.kind ~= "end" then q.done = true Run(q) end
	end
	for j = 1, qn do
		local q = queue[j]
		if not q.done and q.kind == "end" then q.done = true Run(q) end
	end
	qn = 0
	self.busy = false
end

function Bd:Bump(dir)
	local o = R.DIRS[dir]
	if not o or not state then return end
	MoveActor(tank, state.tx + o[1] * 0.18, state.ty + o[2] * 0.18, state.tx, state.ty, 0.12, 0)
	Au:Play("bump")
end

function Bd:Rewind()
	tintTex:Show()
	tintTex:SetAlpha(1)
	self.tint = 0.28
	Au:Play("undo")
end

-- ------------------------------------------------------------------ driver
function Bd:Update(dt)
	if self.busy then
		clock = clock + dt
		for j = 1, qn do
			local q = queue[j]
			if not q.done and q.at <= clock then
				q.done = true
				Bd.tag = q.kind == "end" and "end of a turn" or "turn playback"
				Run(q)
			end
		end
	end
	UpdateActor(tank, dt)
	for i = 1, #party do UpdateActor(party[i], dt) end
	if board then
		for i = 1, #board.mobs do UpdateActor(mobs[i], dt) end
		for i = 1, #board.mobs do
			local z = zzz[i]
			if z.an then
				z.t = z.t + dt
				local an = z.an
				local f = floor(z.t * an.fps) % #an + 1
				local cx, cy = TileXY(z.x, z.y)
				Place(z.tex, cx + T * 0.32, cy + T * 0.95 + (z.t % 1) * T * 0.15, T * 0.5, T * 0.5)
				A:Frame(z.tex, an, f)
			end
		end
	end
	for i = 1, N_FX do
		local e = fx[i]
		if e.an then UpdateFX(e, dt) end
	end
	-- water and lava: one clock for every terrain tile, coordinates changed only on a new frame
	if terrainN > 0 then
		terrainClock = terrainClock + dt
		local f = floor(terrainClock * 8) % 8 + 1
		if f ~= terrainFrame then
			terrainFrame = f
			for i = 1, terrainN do
				local e = terrain[i]
				A:Frame(e.tex, e.an, f)
			end
		end
	end
	if self.partyFlash then
		self.partyFlash = self.partyFlash - dt
		if self.partyFlash <= 0 then self.partyFlash = nil partyTex:SetAlpha(0.6) else partyTex:SetAlpha(0.6 + 0.8 * self.partyFlash) end
	end
	if self.tint then
		self.tint = self.tint - dt
		if self.tint <= 0 then self.tint = nil tintTex:Hide() else tintTex:SetAlpha(self.tint / 0.28) end
	end
	if self.mouseIn then self:HoverUpdate() end
end

-- ------------------------------------------------------------------ mouse
function Bd:TileAtCursor()
	if not board or not bf:IsMouseOver() then return nil end
	local x, y = GetCursorPosition()
	local s = bf:GetEffectiveScale()
	x, y = x / s - bf:GetLeft(), bf:GetTop() - y / s
	local tx, ty = floor(x / T) + 1, floor(y / T) + 1
	if tx < 1 or ty < 1 or tx > board.w or ty > board.h then return nil end
	return tx, ty
end

local lastHX, lastHY
function Bd:HoverUpdate()
	local x, y = self:TileAtCursor()
	if x == lastHX and y == lastHY then return end
	lastHX, lastHY = x, y
	if self.busy then return end
	self.tag = "mouse over a new tile"
	if self.onHover then P:Safe("hover", self.onHover, x, y) end
end

-- the cursor crosses tiles all the time, so the preview does as little as it can: a dot keeps its place and
-- colour when the new path shares it, only dots and rings actually shown are hidden, and "would this step
-- wake something" is worked out once per tile per turn (Bd.ver changes whenever the state does)
local dotsShown, dangerShown = 0, 0
local dotKey = {}            -- per dot: x * 4096 + y * 16 + look, of what it shows now
HideDots = function(from)        -- (declared near the top: Bd:Load uses it)
	from = from or 1
	for i = from, dotsShown do dotTex[i]:Hide() dotKey[i] = nil end
	if from <= dotsShown then dotsShown = from - 1 end
end
local function HideDanger()
	for i = 1, dangerShown do dangerTex[i]:Hide() end
	dangerShown = 0
end
Bd.HideDots = function() HideDots() end
function Bd:DotCount() return dotsShown, dangerShown end

-- one dot: placed only if it changed (look 1 path, 2 past the waking step, 3+ a patrol route)
local DOT_LOOK = { { 0.34, 1, 0.92, 0.7, 1 }, { 0.26, 0.7, 0.55, 0.45, 0.45 } }
local function Dot(k, x, y, look, r, g, b, alpha, size)
	local key = x * 4096 + y * 16 + look
	local d = dotTex[k]
	if dotKey[k] ~= key then
		dotKey[k] = key
		local cx, cy = TileXY(x, y)
		Place(d, cx, cy, T * size, T * size)
		d:SetVertexColor(r, g, b)
		d:SetAlpha(alpha)
		d:Show()
	end
	if k > dotsShown then dotsShown = k end
end
Bd.Dot = Dot

local dangerVer, dangerAt = nil, {}
local function Wakes(i, m, sm, x, y)
	if not sm.alive or sm.awake then return false end
	if R.KINDS[m.kind].ambush then return R.Adjacent(x, y, sm.x, sm.y) end
	return R.Within(x - sm.x, y - sm.y, m.ring) and R:Sees(board, sm.x, sm.y, x, y)
end
local function DangerAt(x, y)
	if dangerVer ~= Bd.ver then dangerVer = Bd.ver wipe(dangerAt) end
	local i = (y - 1) * board.w + x
	local v = dangerAt[i]
	if v == nil then
		v = false
		for j, m in ipairs(board.mobs) do
			if Wakes(j, m, state.mobs[j], x, y) then v = true break end
		end
		dangerAt[i] = v
	end
	return v
end

function Bd:ClearHover(keepTip, keepDots)
	lastHX, lastHY = nil, nil
	ringTex:Hide()
	HideDanger()
	if not keepDots then HideDots() end
	if not keepTip then UI:HideTip() end
	if self.highlighted then self.highlighted = nil UI:HideTip() end
end

-- footstep dots along a path ({x1, y1, x2, y2, ...}), danger rings under mobs the path would wake
function Bd:Preview(path, color, count)
	HideDanger()
	if not path or not board then HideDots() return end
	local n = min(N_DOT, (count or #path) / 2)
	local stopAt
	for k = 1, n do
		local x, y = path[k * 2 - 1], path[k * 2]
		if stopAt then
			local L = DOT_LOOK[2]
			Dot(k, x, y, 2, L[2], L[3], L[4], L[5], L[1])
		else
			local L = DOT_LOOK[1]
			if color then Dot(k, x, y, 4, color[1], color[2], color[3], 1, L[1])
			else Dot(k, x, y, 1, L[2], L[3], L[4], L[5], L[1]) end
			if DangerAt(x, y) then
				stopAt = k
				-- the rings of everything this step wakes; the walk stops here, later dots are dimmed
				for i, m in ipairs(board.mobs) do
					local sm = state.mobs[i]
					if dangerShown < N_DANGER and Wakes(i, m, sm, x, y) then
						dangerShown = dangerShown + 1
						local dt = dangerTex[dangerShown]
						local mx, my = TileXY(sm.x, sm.y)
						local size = (max(1, m.ring) + 0.5) * 2 * T
						Place(dt, mx, my, size, size)
						dt:SetVertexColor(1, 0.35, 0.2, 0.6)
						dt:Show()
					end
				end
			end
		end
	end
	HideDots(n + 1)
end

-- a mob under the cursor: its ring (dashed, tinted), the tooltip with its rules
function Bd:Highlight(i)
	if not board or not state then return end
	local m, sm = board.mobs[i], state.mobs[i]
	if not m or not sm.alive then return end
	local k = R.KINDS[m.kind]
	local cx, cy = TileXY(sm.x, sm.y)
	if not sm.awake then
		local size = (max(1, m.ring) + 0.5) * 2 * T
		Place(ringTex, cx, cy, size, size)
		ringTex:SetVertexColor(1, 0.75, 0.3, 0.9)
		ringTex:Show()
		if m.route then
			-- its loop, from where it stands now
			local route, x, y, pts = m.route, sm.x, sm.y, {}
			for j = 0, #route - 1 do
				local o = R.DIRS[route:sub((sm.pi + j) % #route + 1, (sm.pi + j) % #route + 1)]
				x, y = x + o[1], y + o[2]
				pts[#pts + 1] = x
				pts[#pts + 1] = y
			end
			local nd = min(N_DOT, #pts / 2)
			for j = 1, nd do
				Dot(j, pts[j * 2 - 1], pts[j * 2], 3, 1, 0.6, 0.35, 1 - 0.5 * j / (#pts / 2), 0.28)
			end
			HideDots(nd + 1)
		end
	end
	hoverAnchor:ClearAllPoints()
	hoverAnchor:SetPoint("CENTER", bf, "TOPLEFT", cx + T * 0.4, cy + T * 0.6)
	local lines = {}
	if k.ambush and not sm.awake then
		lines[#lines + 1] = "A closed sarcophagus. It opens when you stand right next to it."
	elseif m.route and not sm.awake then
		lines[#lines + 1] = ("On patrol: walks its loop and notices you inside its ring (%d tiles) where it can see you."):format(m.ring)
	else
		lines[#lines + 1] = sm.awake and "Awake: it walks toward you." or ("Asleep. Wakes if you step inside its ring (" .. m.ring .. " tiles) where it can see you.")
	end
	if k.elite then lines[#lines + 1] = "Elite." end
	if k.statue then lines[#lines + 1] = "Moves only while he can see you: break his sight and he stands like stone." end
	if k.speed > 1 then lines[#lines + 1] = "Fast: moves " .. k.speed .. " tiles a turn." end
	if k.cast then lines[#lines + 1] = ("Caster: while it sees you within %d tiles it casts for %d turns, then hits for %d. Break its sight to stop the cast."):format(k.cast.range, k.cast.turns, k.cast.damage) end
	if k.cast and k.cast.fear then lines[#lines + 1] = "Its wail also knocks you one tile away from it." end
	lines[#lines + 1] = ("Hits for %d. Inside the green party ring, Kesk and Wyn kill it in %d turn%s."):format(k.hit, k.kill, k.kill == 1 and "" or "s")
	if m.link then lines[#lines + 1] = "Chained: its whole pack wakes together." end
	if k.callsFamily then lines[#lines + 1] = "When it wakes, its whole crew in the room wakes too." end
	UI:ShowTip(hoverAnchor, k.name, table.concat(lines, "\n"))
	self.highlighted = i
end

-- the lantern hint: dots toward the next move of the room's best solution
function Bd:Hint(dir)
	if not state or not dir then return end
	if dir == "." then
		self:Preview({ state.tx, state.ty }, { 0.6, 0.85, 1 })
		return
	end
	local o = R.DIRS[dir]
	self:Preview({ state.tx + o[1], state.ty + o[2] }, { 0.6, 0.85, 1 })
end

function Bd:Tile() return T end
