local addonName, ns = ...

local MODULE = "LayerHop"
local SV = "MerrinxUI_LayerHopDB"
local VERB = "hop"
local COMMAND = "layerhop"
local ACTION = "Hop"
local OPTIONS = "GetTabOptions"

assert(addonName == "MerrinxUI_" .. MODULE, "addonName mismatch")

local AceAddon = LibStub("AceAddon-3.0")

local function noop() end

local host, api

if AceAddon:GetAddon(addonName, true) then
	ns.inert = true
	print(addonName .. ": disabled, your MerrinxUI still includes it; update MerrinxUI")
else
	host = AceAddon:GetAddon("MerrinxUI", true)
	if host and type(host.GetPluginAPI) == "function" then
		api = host:GetPluginAPI(1)
	end
end

ns.inert = ns.inert or false
ns.integrated = api ~= nil

ns.appName = ns.integrated and "MerrinxUI" or addonName
ns.slashHint = ns.integrated and "/mui hop" or "/layerhop"
ns.optionsHint = ns.integrated and "/mui > QoL > Layer Hop" or "/layerhop config"
ns.Debug = (api and api.Debug) or { Log = noop, RegisterChecks = noop }

local feature
local optionsRegistered = false

function ns.NewFeature(name, ...)
	if ns.integrated then
		feature = host:NewModule(name, ...)
		host:RegisterSlash(VERB, function()
			feature[ACTION](feature)
		end)
	else
		feature = AceAddon:NewAddon(addonName, "AceConsole-3.0", ...)
		feature:RegisterChatCommand(COMMAND, function(input)
			local arg = (input or ""):match("^%s*(.-)%s*$"):lower()
			if arg == "config" then
				ns.OpenOptions()
			else
				feature[ACTION](feature)
			end
		end)
	end
	return feature
end

function ns.NewDB(name, defaults)
	if ns.integrated then
		return host.db:RegisterNamespace(name, defaults)
	end
	return LibStub("AceDB-3.0"):New(SV, defaults, true)
end

function ns.Print(text)
	if ns.integrated then
		host:Print(text)
	else
		feature:Print(text)
	end
end

function ns.NotifyOptions(page)
	if ns.integrated then
		if api.OptionsWindow:CurrentPage() == page or api.OptionsWindow:CurrentTab() == page then
			LibStub("AceConfigRegistry-3.0"):NotifyChange("MerrinxUI")
		end
	else
		LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
	end
end

function ns.OpenOptions()
	if not optionsRegistered then
		LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, function()
			return feature[OPTIONS](feature)
		end)
		optionsRegistered = true
	end
	LibStub("AceConfigDialog-3.0"):Open(addonName)
end
