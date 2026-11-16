local addonName, ns = ...

local L = ns.LayerHopLogic

BINDING_NAME_MERRINXUI_LAYERHOP = "Toggle the layer hop window"
BINDING_HEADER_MERRINXUI_LAYERHOP = "MerrinxUI Layer Hop"

local PAGE = "Layer Hop"
local CHANNEL = "MerrinxUIHop"
local JOIN_DELAY = 10
local TICK = 1
local COOLDOWN = 10
local ASK_TIMEOUT = 10
local CONFIRM_WAIT = 3
local INVITE_TIMEOUT = 20
local LAND_TIMEOUT = 60
local OFFER_TTL = 30
local MAX_OFFERS = 5
local MAX_WHISPERS = 8
local GENERAL_WINDOW = 30
local GENERAL_TIMEOUT = 60
local GENERAL_TEXT = "Could someone on another layer /inv me for a layer hop? I leave right after, thanks!"
local SURVEY_TTL = 25
local SURVEY_MAX = 40

if ns.inert then
	return
end

local LayerHop = ns.NewFeature("LayerHop", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		host = true,
	},
}

local function plain(v)
	if issecretvalue(v) then
		return nil
	end
	return v
end

local function send(text, chatType, target)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, L.PREFIX, text, chatType, target)
	local sent = ok and result ~= false and (type(result) ~= "number" or result == 0)
	if not sent then
		ns.Debug:Log("LayerHop", "send failed", chatType, ok, result)
	end
	return sent
end

local function channelRestricted()
	return type(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == "function"
		and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() == true
end

local function playerMap()
	local map = plain(C_Map.GetBestMapForUnit("player"))
	if type(map) ~= "number" then
		return nil
	end
	return map
end

local function inInstance()
	return plain(IsInInstance()) == true
end

local function layerLine(self)
	local map, zone = self:CurrentLayer()
	if zone then
		local info = C_Map.GetMapInfo(map)
		return "Current layer  |cffffffff" .. zone .. (info and (" in " .. info.name) or "") .. "|r"
	end
	return "Current layer  |cffffffffunknown, target or mouse over an NPC|r"
end

local function currentSurvey(self, map, zone)
	local s = self.survey
	if s and s.map == map and s.zone == zone then
		return s
	end
	return nil
end

local function canAskGeneral(hop, generalUntil, now, survey)
	if hop then
		return false
	end
	if generalUntil and now < generalUntil then
		return true
	end
	return survey ~= nil and survey.routes == 0
end

function LayerHop:OnInitialize()
	self.db = ns.NewDB("LayerHop", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.layer = L.NewLayer()
	self.offers = {}
	self.stats = { asked = 0, offers = 0, invites = 0, hops = 0 }
	self.language = L.Language(GetLocale())
	self.window = ns.LayerHopWindow.New(self)
end

function LayerHop:OnEnable()
	C_ChatInfo.RegisterAddonMessagePrefix(L.PREFIX)
	self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnMouseover")
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNamePlateAdded")
	self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInvite")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	-- Joining late keeps the hidden channel from taking General's or Trade's number at login.
	self.joinTimer = C_Timer.NewTimer(JOIN_DELAY, function()
		self.joinTimer = nil
		self:JoinChannel()
	end)
	self:Scan()
end

function LayerHop:OnDisable()
	if self.joinTimer then
		self.joinTimer:Cancel()
		self.joinTimer = nil
	end
	self:Finish()
	self.window:Close()
	self.survey = nil
	if GetChannelName(CHANNEL) ~= 0 then
		LeaveChannelByName(CHANNEL)
	end
end

function LayerHop:Refresh()
	if self.db.profile.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function LayerHop:Say(text)
	ns.Print("Layer Hop: " .. text)
end

function LayerHop:Notify()
	ns.NotifyOptions(PAGE)
	self.window:Refresh()
end

function LayerHop:JoinChannel()
	if GetChannelName(CHANNEL) == 0 then
		JoinTemporaryChannel(CHANNEL)
	end
	if type(ChatFrame_RemoveChannel) == "function" then
		for _, name in ipairs(CHAT_FRAMES) do
			ChatFrame_RemoveChannel(_G[name], CHANNEL)
		end
	end
	ns.Debug:Log("LayerHop", "channel", GetChannelName(CHANNEL))
end

function LayerHop:Observe(unit)
	local guid = plain(UnitGUID(unit))
	local zone = L.ParseGUID(guid)
	local map = zone and playerMap()
	if map and L.Observe(self.layer, map, zone, guid) then
		ns.Debug:Log("LayerHop", "layer", map, zone)
		self:OnLayerChanged()
		self:Notify()
	end
end

function LayerHop:Scan()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		self:Observe(plate.unitToken)
	end
	self:Observe("target")
end

function LayerHop:OnTargetChanged()
	self:Observe("target")
end

function LayerHop:OnMouseover()
	self:Observe("mouseover")
end

function LayerHop:OnNamePlateAdded(_, unit)
	self:Observe(unit)
end

function LayerHop:CurrentLayer()
	local map = playerMap()
	return map, L.Current(self.layer, map)
end

function LayerHop:RosterNames()
	local names = {}
	for i = 1, GetNumDisplayChannels() do
		local name, _, _, _, count = GetChannelDisplayInfo(i)
		if type(name) == "string" and name:lower() == CHANNEL:lower() and type(count) == "number" then
			for j = 1, count do
				local ok, member = pcall(C_ChatInfo.GetChannelRosterInfo, i, j)
				member = ok and plain(member)
				if type(member) == "string" and member ~= "" then
					names[#names + 1] = member
				end
			end
			break
		end
	end
	return names
end

-- Forever can refuse addon messages on custom channels, so the request then goes as
-- whispers to a few members of the channel instead.
function LayerHop:Broadcast(text)
	local routes = 0
	local channel = GetChannelName(CHANNEL)
	if channel ~= 0 then
		if not channelRestricted() then
			if send(text, "CHANNEL", tostring(channel)) then
				routes = routes + 1
			end
		else
			local me = UnitName("player")
			local targets = L.Sample(self:RosterNames(), MAX_WHISPERS, math.random, function(name)
				return L.SameName(name, me)
			end)
			for _, target in ipairs(targets) do
				if send(text, "WHISPER", target) then
					routes = routes + 1
				end
			end
		end
	end
	if IsInGuild() and send(text, "GUILD") then
		routes = routes + 1
	end
	return routes
end

function LayerHop:ToggleWindow()
	if not self:IsEnabled() then
		return self:Say("turned off in " .. ns.optionsHint .. ".")
	end
	if self.window:IsShown() then
		return self.window:Close()
	end
	self:OpenWindow()
end

function LayerHop:OpenWindow()
	self:Scan()
	self.window:Open()
	self:MaybeSurvey()
end

function LayerHop:Survey(map, zone)
	local now = GetTime()
	local id = math.random(1, L.MAX_ID)
	local routes = self:Broadcast(L.Encode("Q", id, map, zone))
	self.lastAsk = now
	local survey = { id = id, map = map, zone = zone, at = now, routes = routes, offers = {}, excluded = {} }
	self.survey = survey
	if routes > 0 then
		self.stats.asked = self.stats.asked + 1
	end
	C_Timer.After(CONFIRM_WAIT, function()
		if self.survey == survey then
			self:Notify()
		end
	end)
	self:Notify()
	return survey
end

function LayerHop:MaybeSurvey()
	if not self:IsEnabled() or self.hop or inInstance() then
		return
	end
	local map, zone = self:CurrentLayer()
	if not zone then
		return
	end
	local now = GetTime()
	local s = self.survey
	if s and s.map == map and s.zone == zone and now - s.at <= SURVEY_TTL then
		return
	end
	if self.lastAsk and now - self.lastAsk < COOLDOWN then
		return
	end
	self:Survey(map, zone)
end

function LayerHop:CheckLayers()
	if self.hop then
		return self:Say("already looking for another layer.")
	end
	self:Scan()
	local map, zone = self:CurrentLayer()
	if not zone then
		return self:Say("layer unknown. Target or mouse over an NPC first.")
	end
	if inInstance() then
		return self:Say("layers only exist in the open world.")
	end
	local now = GetTime()
	if self.lastAsk and now - self.lastAsk < COOLDOWN then
		return self:Say(string.format("wait %d more seconds.", math.ceil(COOLDOWN - (now - self.lastAsk))))
	end
	self:Survey(map, zone)
end

function LayerHop:HopTo(target)
	if not self:IsEnabled() then
		return self:Say("turned off in " .. ns.optionsHint .. ".")
	end
	if self.hop then
		return self:Say("already looking for another layer.")
	end
	if IsInGroup() then
		return self:Say("leave your group first.")
	end
	if inInstance() then
		return self:Say("layers only exist in the open world.")
	end
	if InCombatLockdown() then
		return self:Say("you can't change layer in combat.")
	end
	self:Scan()
	local map, zone = self:CurrentLayer()
	if not zone then
		return self:Say("layer unknown. Target or mouse over an NPC first.")
	end

	local now = GetTime()
	local s = self.survey
	if s and s.map == map and s.zone == zone and now - s.at <= SURVEY_TTL then
		if s.routes == 0 then
			if target.kind == "any" then
				self:AskGeneral(map, zone)
			else
				self:OfferGeneral("could not reach other MerrinxUI users.")
			end
			return
		end
		local sender, sure = L.Choose(s.offers, { map = map, zone = zone }, target, self.language, math.random)
		local age = now - s.at
		if sender and (sure or now >= s.at + CONFIRM_WAIT) then
			self:Start({
				id = s.id,
				state = "asking",
				map = map,
				zone = zone,
				target = target,
				fallbackAt = now,
				deadline = now + ASK_TIMEOUT,
			})
			self:Pick(self.hop, sender)
			return
		elseif age < ASK_TIMEOUT then
			self:Start({
				id = s.id,
				state = "asking",
				map = map,
				zone = zone,
				target = target,
				fallbackAt = s.at + CONFIRM_WAIT,
				deadline = s.at + ASK_TIMEOUT,
			})
			self:Say("looking for a player on another layer.")
			return
		end
	end

	if self.lastAsk and now - self.lastAsk < COOLDOWN then
		return self:Say(string.format("wait %d more seconds.", math.ceil(COOLDOWN - (now - self.lastAsk))))
	end
	s = self:Survey(map, zone)
	if s.routes == 0 then
		if target.kind == "any" then
			self:AskGeneral(map, zone)
		else
			self:OfferGeneral("could not reach other MerrinxUI users.")
		end
		return
	end
	self:Start({
		id = s.id,
		state = "asking",
		map = map,
		zone = zone,
		target = target,
		fallbackAt = now + CONFIRM_WAIT,
		deadline = now + ASK_TIMEOUT,
	})
	self:Say("looking for a player on another layer.")
end

function LayerHop:Evaluate(hop)
	local offers = (self.survey and self.survey.id == hop.id) and self.survey.offers or {}
	local sender, sure = L.Choose(offers, { map = hop.map, zone = hop.zone }, hop.target, self.language, math.random)
	if sender and (sure or GetTime() >= hop.fallbackAt) then
		self:Pick(hop, sender)
	end
end

-- Chat channels only accept messages sent during a key press or click, so this has to run
-- straight from a click and never from a timer.
function LayerHop:AskGeneral(map, zone)
	local now = GetTime()
	if self.lastGeneral and now - self.lastGeneral < COOLDOWN then
		return self:Say(string.format("wait %d more seconds.", math.ceil(COOLDOWN - (now - self.lastGeneral))))
	end
	self.generalUntil = nil
	local channel = plain(C_ChatInfo.GetGeneralChannelLocalID())
	if type(channel) ~= "number" then
		return self:Say("join the General channel first.")
	end
	local ok, err = pcall(C_ChatInfo.SendChatMessage, GENERAL_TEXT, "CHANNEL", nil, channel)
	if not ok then
		ns.Debug:Log("LayerHop", "general failed", err)
		return self:Say("could not post in General.")
	end
	self.lastGeneral = now
	self:Start({ state = "public", map = map, zone = zone, deadline = now + GENERAL_TIMEOUT })
	self:Say("asked in General for an invite.")
end

function LayerHop:Start(hop)
	self.hop = hop
	self.ticker = C_Timer.NewTicker(TICK, function()
		self:OnTick()
	end)
	self:Notify()
end

function LayerHop:OfferGeneral(text)
	self.generalUntil = GetTime() + GENERAL_WINDOW
	local message = string.format("%s Use Ask in General in the hop window within %d seconds.", text, GENERAL_WINDOW)
	if self.hop then
		self:Finish(message)
	else
		self:Say(message)
	end
	C_Timer.After(GENERAL_WINDOW, function()
		self:Notify()
	end)
	self:Notify()
end

function LayerHop:BindingHop()
	self:ToggleWindow()
end

function LayerHop:Finish(text)
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	if not self.hop then
		return
	end
	self.hop = nil
	if text then
		self:Say(text)
	end
	self:Notify()
end

function LayerHop:Leave()
	if IsInGroup() then
		C_PartyInfo.LeaveParty()
	end
end

function LayerHop:OnTick()
	local hop = self.hop
	if not hop then
		return self:Finish()
	end
	self:Scan()
	if self.hop ~= hop then
		return
	end
	local now = GetTime()
	if hop.state == "asking" then
		self:Evaluate(hop)
		if self.hop ~= hop or hop.state ~= "asking" then
			return
		end
	end
	if now < hop.deadline then
		return
	end
	if hop.state == "asking" then
		self:OfferGeneral("no MerrinxUI user on another layer answered.")
	elseif hop.state == "picked" then
		self:OfferGeneral("no invite arrived.")
	elseif hop.state == "public" then
		self:Finish("nobody in General invited you.")
	else
		self:Leave()
		self:Finish("the layer did not change, so you left the group.")
	end
end

function LayerHop:OnLayerChanged()
	local map, zone = self:CurrentLayer()
	local s = self.survey
	if s and (s.map ~= map or s.zone ~= zone) then
		self.survey = nil
	end
	local hop = self.hop
	if hop and hop.state == "joined" and map == hop.map and zone and zone ~= hop.zone then
		self.stats.hops = self.stats.hops + 1
		self:Leave()
		self:Finish("moved to layer " .. zone .. ".")
	end
	if self.window:IsShown() then
		self:MaybeSurvey()
	end
end

function LayerHop:OnRoster()
	local hop = self.hop
	if not hop then
		return
	end
	local grouped = IsInGroup()
	if (hop.state == "picked" or hop.state == "accepted") and grouped then
		hop.state, hop.deadline = "joined", GetTime() + LAND_TIMEOUT
		self:Notify()
	elseif hop.state == "joined" and not grouped then
		self:Finish("the group ended before the layer changed.")
	end
end

function LayerHop:OnPartyInvite(_, inviter)
	local hop = self.hop
	inviter = plain(inviter)
	if not L.AcceptsInvite(hop, inviter) then
		return
	end
	hop.state, hop.host = "accepted", inviter
	local ok = pcall(AcceptGroup)
	if ok then
		StaticPopup_Hide("PARTY_INVITE")
	end
	ns.Debug:Log("LayerHop", "accept", ok)
end

function LayerHop:OnAddonMessage(_, prefix, text, _, sender)
	if plain(prefix) ~= L.PREFIX then
		return
	end
	local msg = L.Decode(plain(text))
	sender = plain(sender)
	if not msg or type(sender) ~= "string" or sender == "" then
		return
	end
	if msg.kind == "Q" then
		self:OnQuery(msg, sender)
	elseif msg.kind == "O" then
		self:OnOffer(msg, sender)
	else
		self:OnPick(msg, sender)
	end
end

function LayerHop:OnQuery(msg, sender)
	if self.hop or self.offers[msg.id] or L.Prune(self.offers, GetTime(), OFFER_TTL) >= MAX_OFFERS then
		return
	end
	local map, zone = self:CurrentLayer()
	local host = {
		hosting = self.db.profile.host,
		grouped = IsInGroup(),
		instance = inInstance(),
		combat = InCombatLockdown(),
		map = map,
		zone = zone,
	}
	if L.CanHost(host, msg) and send(L.Encode("O", msg.id, map, zone, GetLocale()), "WHISPER", sender) then
		self.offers[msg.id] = { sender = sender, at = GetTime() }
		self.stats.offers = self.stats.offers + 1
	end
end

function LayerHop:OnOffer(msg, sender)
	local s = self.survey
	if not s or msg.id ~= s.id or s.excluded[L.ShortName(sender)] then
		return
	end
	local offer = { sender = sender, map = msg.map, zone = msg.zone, language = L.Language(msg.locale) }
	if not L.AddOffer(s.offers, offer, SURVEY_MAX) then
		return
	end
	local hop = self.hop
	if hop and hop.state == "asking" and hop.id == s.id then
		self:Evaluate(hop)
	end
	self:Notify()
end

function LayerHop:Pick(hop, host)
	local s = self.survey
	if s then
		for i = #s.offers, 1, -1 do
			if L.SameName(s.offers[i].sender, host) then
				table.remove(s.offers, i)
			end
		end
		s.excluded[L.ShortName(host)] = true
	end
	if send(L.Encode("P", hop.id), "WHISPER", host) then
		hop.state, hop.host, hop.deadline = "picked", host, GetTime() + INVITE_TIMEOUT
		self:Say("asking " .. host .. " for an invite.")
		self:Notify()
	end
end

function LayerHop:OnPick(msg, sender)
	local offer = self.offers[msg.id]
	if not offer or not L.SameName(offer.sender, sender) or GetTime() - offer.at > OFFER_TTL then
		return
	end
	self.offers[msg.id] = nil
	if IsInGroup() or InCombatLockdown() then
		return
	end
	C_PartyInfo.InviteUnit(sender)
	self.stats.invites = self.stats.invites + 1
	self:Say("inviting " .. sender .. " so they can change layer.")
end

function LayerHop:AskGeneralNow()
	if self.hop then
		return self:Say("already looking for another layer.")
	end
	if IsInGroup() then
		return self:Say("leave your group first.")
	end
	if inInstance() then
		return self:Say("layers only exist in the open world.")
	end
	if InCombatLockdown() then
		return self:Say("you can't change layer in combat.")
	end
	local map, zone = self:CurrentLayer()
	if not zone then
		return self:Say("layer unknown. Target or mouse over an NPC first.")
	end
	if not canAskGeneral(self.hop, self.generalUntil, GetTime(), currentSurvey(self, map, zone)) then
		return self:Say("try a hop first.")
	end
	self:AskGeneral(map, zone)
end

function LayerHop:Cancel()
	local hop = self.hop
	if hop and (hop.state == "accepted" or hop.state == "joined") then
		self:Leave()
	end
	self:Finish("cancelled.")
end

local STATUS = {
	asking = "Looking for a player on another layer...",
	picked = "Waiting for an invite...",
	public = "Asked in General, waiting for an invite...",
	accepted = "Joining the group...",
	joined = "In the group, waiting for the layer to change...",
}

function LayerHop:StatusText()
	local lines = {}
	lines[1] = layerLine(self)
	local channel = GetChannelName(CHANNEL)
	local route
	if channel == 0 then
		route = "not joined"
	elseif channelRestricted() then
		route = "joined, requests go as whispers"
	else
		route = "joined"
	end
	lines[2] = "Hop channel  |cffffffff" .. route .. "|r"
	lines[3] = "Status  |cffffffff" .. (self.hop and STATUS[self.hop.state] or "idle") .. "|r"
	lines[4] =
		string.format("This session  |cffffffff%d hops, %d players helped|r", self.stats.hops, self.stats.invites)
	return table.concat(lines, "\n")
end

function LayerHop:WindowModel()
	local map, zone = self:CurrentLayer()
	local now = GetTime()
	local hop = self.hop
	local s = currentSurvey(self, map, zone)

	local status
	if hop then
		status = STATUS[hop.state]
	elseif not zone then
		status = "Target or mouse over an NPC to read your layer."
	elseif not s then
		status = "Press Check again to ask other MerrinxUI users."
	elseif s.routes == 0 then
		status = "Could not reach other MerrinxUI users."
	elseif now - s.at < CONFIRM_WAIT then
		status = "Asking other MerrinxUI users..."
	elseif #s.offers == 0 then
		status = "Nobody answered."
	else
		local n = #s.offers
		status = string.format("%d player%s answered.", n, n == 1 and "" or "s")
	end

	return {
		layerText = layerLine(self),
		languageText = string.format(
			"Your client language: %s. Forever groups layers by Preferred Online Language "
				.. "(Options > System > Languages and Social).",
			self.language or "unknown"
		),
		status = status,
		rows = s and L.Rows(s.offers, { map = map, zone = zone }, self.language) or {},
		busy = hop ~= nil,
		canAskGeneral = canAskGeneral(hop, self.generalUntil, now, s),
		statsText = string.format("This session: %d hops, %d players helped", self.stats.hops, self.stats.invites),
	}
end

function LayerHop:GetTabOptions()
	return {
		type = "group",
		name = PAGE,
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = function()
					return self.db.profile.enabled
				end,
				set = function(_, value)
					self.db.profile.enabled = value
					self:Refresh()
				end,
			},
			host = {
				type = "toggle",
				name = "Help others hop",
				order = 2,
				desc = "Invite MerrinxUI users from other layers or zones while you are solo and out of combat.",
				get = function()
					return self.db.profile.host
				end,
				set = function(_, value)
					self.db.profile.host = value
				end,
			},
			hop = {
				type = "execute",
				name = "Open hop window",
				order = 3,
				desc = "Opens the layer hop window, which shows your current layer, client language and lets "
					.. "you hop to another layer.",
				disabled = function()
					return not self:IsEnabled()
				end,
				func = function()
					self:OpenWindow()
				end,
			},
			statusHeader = { type = "header", name = "Status", order = 10 },
			status = {
				type = "description",
				order = 11,
				name = function()
					return self:StatusText()
				end,
			},
			keyHeader = { type = "header", name = "Key binding", order = 20 },
			key = {
				type = "description",
				order = 21,
				name = function()
					local key = GetBindingKey("MERRINXUI_LAYERHOP")
					local bound = key and ("Bound to |cffffffff" .. GetBindingText(key) .. "|r. ") or "Not bound. "
					return bound
						.. "Set it under Options > Key Bindings > AddOns > MerrinxUI Layer Hop > Toggle the layer hop window, "
						.. "or use "
						.. ns.slashHint
						.. "."
				end,
			},
		},
	}
end

function LayerHop:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					["C_ChatInfo.SendAddonMessage"] = C_ChatInfo and C_ChatInfo.SendAddonMessage,
					["C_ChatInfo.RegisterAddonMessagePrefix"] = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,
					["C_ChatInfo.GetChannelRosterInfo"] = C_ChatInfo and C_ChatInfo.GetChannelRosterInfo,
					["C_ChatInfo.SendChatMessage"] = C_ChatInfo and C_ChatInfo.SendChatMessage,
					["C_ChatInfo.GetGeneralChannelLocalID"] = C_ChatInfo and C_ChatInfo.GetGeneralChannelLocalID,
					["C_PartyInfo.InviteUnit"] = C_PartyInfo and C_PartyInfo.InviteUnit,
					["C_PartyInfo.LeaveParty"] = C_PartyInfo and C_PartyInfo.LeaveParty,
					["C_Map.GetBestMapForUnit"] = C_Map and C_Map.GetBestMapForUnit,
					["C_Map.GetMapInfo"] = C_Map and C_Map.GetMapInfo,
					JoinTemporaryChannel = JoinTemporaryChannel,
					LeaveChannelByName = LeaveChannelByName,
					GetChannelName = GetChannelName,
					GetNumDisplayChannels = GetNumDisplayChannels,
					GetChannelDisplayInfo = GetChannelDisplayInfo,
					AcceptGroup = AcceptGroup,
					StaticPopup_Hide = StaticPopup_Hide,
					IsInGuild = IsInGuild,
				}) do
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end
				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS", type(ChatFrame_RemoveChannel) == "function"
			end,
		},
		{
			name = "channel",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if self.joinTimer then
					return "SKIP", "joining soon"
				end
				local channel = GetChannelName(CHANNEL)
				return channel ~= 0 and "PASS" or "FAIL", channel, channelRestricted(), #self:RosterNames()
			end,
		},
		{
			name = "layer",
			run = function()
				local map, zone = self:CurrentLayer()
				return "INFO", map, zone, self.layer.map, self.layer.zone
			end,
		},
		{
			name = "state",
			run = function()
				local hop = self.hop
				return "INFO",
					hop and hop.state or "idle",
					self.stats.asked,
					self.stats.offers,
					self.stats.invites,
					self.stats.hops
			end,
		},
	}
end
