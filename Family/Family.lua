--[[ Body Pull - Family/Family.lua
	Settings in one place, the slash commands, and Body Pull's tile in NetherSuite (all optional:
	Body Pull plays exactly the same alone).

	  P:Setting(key) / P:SetSetting(key, value)   applied at once wherever it is changed
	  /bodypull, /bpull           open or close the game ( /pull is left alone: DBM and BigWigs use it )
	  /bodypull reset             forget this character's Body Pull records (asks first)
	  /bodypull perf              frame time and memory
	  /bodypull debug             errors and missing art ]]

local ADDON, ns = ...
local P = ns.P

local DEFAULTS = { music = true, sound = true, nudge = false, size = 0.9, followNetherUI = true, minimapButton = true,
	shareScores = true, dailyNotice = false }
P.SETTING_DEFAULTS = DEFAULTS

function P:Setting(key)
	local st = self.db and self.db.settings
	local v = st and st[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

function P:SetSetting(key, value)
	if not self.db then return end
	local was = self:Setting(key)
	self.db.settings[key] = value
	if was == value then return end
	local G = self.Game
	if key == "music" then
		if not value then self.Audio:StopMusic()
		elseif G and G.IsOpen and G:IsOpen() and G.board then self.Audio:Music("music_" .. (G.board.delve or "candlewick")) end
	elseif key == "size" then
		if G then G:FitScale() end
	elseif key == "minimapButton" then
		if self.Minimap and self.Minimap.SetShown then self.Minimap:SetShown(value) end
	elseif key == "shareScores" then
		if self.Leaderboard then self.Leaderboard:SetEnabled(value) end
	end
	self:Fire("SETTINGS_CHANGED", key)
end

-- ------------------------------------------------------------------ NetherSuite
local LABELS = {
	{ "music", "Music", { "music", "sound" } },
	{ "sound", "Sound effects", { "sound", "sfx", "effects" } },
	{ "nudge", "Remind me after 20 minutes of play", { "reminder", "nudge", "break", "time" } },
	{ "minimapButton", "Show the minimap button", { "minimap", "button" } },
	{ "shareScores", "Share scores with other players", { "scores", "leaderboard", "share", "channel" } },
	{ "dailyNotice", "Tell me when a new daily room is ready", { "daily", "notice", "toast" } },
	{ "followNetherUI", "Follow NetherUI's theme (options page)", { "theme", "look", "netherui", "skin" } },
}

local function Settings()
	local list = {}
	for _, l in ipairs(LABELS) do
		local key = l[1]
		list[#list + 1] = { id = key, kind = "toggle", label = l[2], page = "general", keywords = l[3],
			get = function() return P:Setting(key) and true or false end,
			set = function(v) P:SetSetting(key, v and true or false) end }
	end
	return list
end

local function Status()
	local Pr = P.Progress
	local lines = {}
	for _, d in ipairs(Pr:Delves()) do
		local cleared, total, medals = Pr:Count(d.id)
		lines[#lines + 1] = { d.name, ("%d / %d rooms, %d / %d medal points"):format(cleared, total, medals, total * 3) }
	end
	return lines
end

local function Descriptor()
	return {
		id = "bodypull", name = "Body Pull", version = P.VERSION, apiVersion = 1, addon = ADDON,
		icon = P.MEDIA .. "Logo", banner = P.MEDIA .. "Banner",
		description = "A turn-based dungeon puzzle: you can't push anything, only pull. Lead each pack to your party in as few steps as you can.",
		category = "Games", slash = { "/bodypull", "/bpull" },
		pages = { { id = "general", label = "General" } },
		settings = Settings(),
		open = function() P.Game:Open() return true end,
		focus = function() if P.Options and P.Options.Open then P.Options:Open() else P.Game:Open() end return true end,
		status = Status,
	}
end

local joined = false
local function JoinSuite()
	if joined then return end
	local S = rawget(_G, "NetherSuite")
	if type(S) == "table" and type(S.RegisterAddon) == "function" then
		joined = pcall(S.RegisterAddon, S, Descriptor())
	elseif C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("NetherSuite") then
		NetherSuite_Queue = NetherSuite_Queue or {}
		table.insert(NetherSuite_Queue, Descriptor())
		joined = true
	end
end

P:Register("LOGIN", JoinSuite)
P:On("ADDON_LOADED", function(_, name)
	if name == "NetherSuite" and P.loggedIn then P:After(0, JoinSuite) end
end)

if NetherFamily then
	if NetherFamily.Slash then NetherFamily:Slash(ADDON, "BODYPULL", "Body Pull") end
end

-- ------------------------------------------------------------------ slash commands
local confirmReset = 0
local function Slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "perf" then
		P.Game:Perf()
	elseif msg == "debug" then
		P.debug = not P.debug
		P:Print("version %s, schema %d, %d error(s), %d missing art; error messages in chat %s.", P.VERSION, P.SCHEMA,
			#P.errors, #P.Assets.missing, P.debug and "on" or "off")
		for _, e in ipairs(P.errors) do P:Print("  %s%s", e.text, e.n > 1 and (" (x" .. e.n .. ")") or "") end
		for _, e in ipairs(P.Assets.missing) do P:Print("  missing: %s", e) end
	elseif msg == "reset" then
		local now = GetTime()
		if now - confirmReset > 10 then
			confirmReset = now
			P:Print("this forgets every room record, medal, daily result, achievement and shield of this character. Type /bodypull reset again within 10 seconds to confirm.")
			return
		end
		confirmReset = 0
		if P.char then
			wipe(P.char.rooms)
			P.char.resume = nil
			P.char.ach, P.char.daily, P.char.dailyDays, P.char.skin, P.char.seal = nil, nil, nil, nil, nil
		end
		P.Game:Forget()
		P:Print("this character's records have been reset.")
	elseif msg == "testrooms" then
		-- for testing: every room open until the next /reload (nothing is saved, no medals given)
		P.testOpen = not P.testOpen
		P:Print("every room is %s for this session.", P.testOpen and "open" or "back to normal")
		if P.Game.RefreshRooms and P.Game.screen == "rooms" then P.Game:RefreshRooms() end
	elseif msg == "daily" then
		P.Game:Open()
		if P.Game:IsOpen() then P.Game:Screen("daily") end
	elseif msg == "help" or msg == "?" then
		P:Print("/bodypull opens the game. Also: /bodypull daily, /bodypull perf, /bodypull debug, /bodypull reset.")
	else
		P.Game:Toggle()
	end
end

SLASH_BODYPULL1 = "/bodypull"
SLASH_BODYPULL2 = "/bpull"
SlashCmdList.BODYPULL = function(msg) P:Safe("slash", Slash, msg) end
