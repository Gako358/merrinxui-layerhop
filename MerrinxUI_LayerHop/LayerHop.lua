local addonName, ns = ...

local L = ns.LayerHopLogic

BINDING_NAME_MERRINXUI_LAYERHOP = "Hop to another layer"
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

function LayerHop:OnInitialize()
	self.db = ns.NewDB("LayerHop", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.layer = L.NewLayer()
	self.offers = {}
	self.stats = { asked = 0, offers = 0, invites = 0, hops = 0 }
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

function LayerHop:Hop()
	if not self:IsEnabled() then
		return self:Say("turned off in " .. ns.optionsHint .. ".")
	end
	if self.hop then
		return self:Say("already looking for another layer.")
	end
	local now = GetTime()
	if self.lastAsk and now - self.lastAsk < COOLDOWN then
		return self:Say(string.format("wait %d more seconds.", math.ceil(COOLDOWN - (now - self.lastAsk))))
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

	self.lastAsk = now
	if self.generalUntil and now < self.generalUntil then
		return self:AskGeneral(map, zone)
	end
	local id = math.random(1, L.MAX_ID)
	if self:Broadcast(L.Encode("Q", id, map, zone)) == 0 then
		return self:AskGeneral(map, zone)
	end
	self.stats.asked = self.stats.asked + 1
	self:Start({
		id = id,
		state = "asking",
		map = map,
		zone = zone,
		fallbackAt = now + CONFIRM_WAIT,
		deadline = now + ASK_TIMEOUT,
	})
	self:Say("looking for a player on another layer.")
end

-- Chat channels only accept messages sent during a key press or click, so this has to run
-- straight from Hop and never from a timer.
function LayerHop:AskGeneral(map, zone)
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
	self:Start({ state = "public", map = map, zone = zone, deadline = GetTime() + GENERAL_TIMEOUT })
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
	self:Finish(string.format("%s Press hop again within %d seconds to ask in General.", text, GENERAL_WINDOW))
end

function LayerHop:BindingHop()
	self:Hop()
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
	if hop.state == "asking" and hop.fallback and now >= hop.fallbackAt then
		local host = hop.fallback
		hop.fallback = nil
		return self:Pick(hop, host)
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
	local hop = self.hop
	if not hop or hop.state ~= "joined" then
		return
	end
	local map, zone = self:CurrentLayer()
	if map == hop.map and zone and zone ~= hop.zone then
		self.stats.hops = self.stats.hops + 1
		self:Leave()
		self:Finish("moved to layer " .. zone .. ".")
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
	if self.hop or L.Prune(self.offers, GetTime(), OFFER_TTL) >= MAX_OFFERS then
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
	if L.CanHost(host, msg) and send(L.Encode("O", msg.id, map, zone), "WHISPER", sender) then
		self.offers[msg.id] = { sender = sender, at = GetTime() }
		self.stats.offers = self.stats.offers + 1
	end
end

function LayerHop:OnOffer(msg, sender)
	local hop = self.hop
	if not hop or hop.state ~= "asking" or msg.id ~= hop.id then
		return
	end
	local other = L.OtherLayer(hop, msg)
	if other then
		self:Pick(hop, sender)
	elseif other == nil and not hop.fallback then
		hop.fallback = sender
	end
end

function LayerHop:Pick(hop, host)
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

local STATUS = {
	asking = "Looking for a player on another layer...",
	picked = "Waiting for an invite...",
	public = "Asked in General, waiting for an invite...",
	accepted = "Joining the group...",
	joined = "In the group, waiting for the layer to change...",
}

function LayerHop:StatusText()
	local map, zone = self:CurrentLayer()
	local lines = {}
	if zone then
		local info = C_Map.GetMapInfo(map)
		lines[1] = "Current layer  |cffffffff" .. zone .. (info and (" in " .. info.name) or "") .. "|r"
	else
		lines[1] = "Current layer  |cffffffffunknown, target or mouse over an NPC|r"
	end
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
				name = "Hop layer",
				order = 3,
				desc = "Joins a MerrinxUI user on another layer, then leaves the group once the layer has changed. "
					.. "If none answers, pressing again asks in General and accepts the first invite.",
				disabled = function()
					return not self:IsEnabled() or self.hop ~= nil
				end,
				func = function()
					self:Hop()
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
						.. "Set it under Options > Key Bindings > AddOns > MerrinxUI Layer Hop > Hop to another layer, "
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
