local addonName, ns = ...

local W = {}
ns.LayerHopWindow = W

W.APP = "MerrinxUI_LayerHop_Window"

function W.Options(model, feature)
	local args = {
		layer = {
			type = "description",
			order = 1,
			name = model.layerText,
			fontSize = "medium",
		},
		language = {
			type = "description",
			order = 2,
			name = model.languageText,
		},
		status = {
			type = "description",
			order = 3,
			name = model.status,
			fontSize = "medium",
		},
		any = {
			type = "execute",
			order = 10,
			width = "full",
			name = "Hop to any other layer",
			disabled = model.busy,
			func = function()
				feature:HopTo({ kind = "any" })
			end,
		},
		check = {
			type = "execute",
			order = 100,
			name = "Check again",
			disabled = model.busy,
			func = function()
				feature:CheckLayers()
			end,
		},
		general = {
			type = "execute",
			order = 101,
			name = "Ask in General",
			hidden = not model.canAskGeneral,
			func = function()
				feature:AskGeneralNow()
			end,
		},
		cancel = {
			type = "execute",
			order = 102,
			name = "Cancel",
			hidden = not model.busy,
			func = function()
				feature:Cancel()
			end,
		},
		stats = {
			type = "description",
			order = 110,
			name = model.statsText,
		},
	}

	for i, row in ipairs(model.rows) do
		args["row" .. i] = {
			type = "execute",
			order = 10 + i,
			width = "full",
			name = row.label,
			disabled = model.busy,
			func = function()
				feature:HopTo(row.target)
			end,
		}
	end

	return {
		type = "group",
		name = "Layer Hop",
		args = args,
	}
end

function W.New(feature)
	local AceConfig = LibStub("AceConfig-3.0")
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")
	local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

	local window = {}
	local registered = false

	function window:Open()
		if not registered then
			AceConfig:RegisterOptionsTable(W.APP, function()
				return W.Options(feature:WindowModel(), feature)
			end)
			AceConfigDialog:SetDefaultSize(W.APP, 440, 420)
			registered = true
		end
		AceConfigDialog:Open(W.APP)
	end

	function window:Close()
		AceConfigDialog:Close(W.APP)
	end

	function window:IsShown()
		return AceConfigDialog.OpenFrames[W.APP] ~= nil
	end

	function window:Refresh()
		if window:IsShown() then
			AceConfigRegistry:NotifyChange(W.APP)
		end
	end

	return window
end
