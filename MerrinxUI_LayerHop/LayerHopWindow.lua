local addonName, ns = ...

local W = {}
ns.LayerHopWindow = W

W.FRAME = "MerrinxUILayerHop"

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local WIDTH = 380
local PAD = 14
local HEADER = 40
local FOOTER = 26
local HOP_BUTTON = 30
local ACTION_BUTTON = 26
local GAP = 6

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

local function byOrder(a, b)
	return a.order < b.order
end

function W.New(feature)
	local Theme = ns.Theme
	local CONTENT_W = WIDTH - 2 * PAD

	local window = {}
	local frame, title, layerText, languageText, statusCard, statusText, hopHeading, statsText
	local hopButtons, actionButtons = {}, {}

	local function setColor(tex, color)
		tex:SetColorTexture(color[1], color[2], color[3], color[4])
	end

	local function setTextColor(fs, color)
		fs:SetTextColor(color[1], color[2], color[3], color[4])
	end

	local function newText(parent, size, color)
		local fs = parent:CreateFontString(nil, "OVERLAY")
		if not fs:SetFont(Theme.font, size, "") then
			fs:SetFont(FALLBACK_FONT, size, "")
		end
		fs:SetJustifyH("LEFT")
		setTextColor(fs, color)
		return fs
	end

	local function paint(button)
		local hovered = button.hovered and button:IsEnabled()
		if button.primary then
			setColor(button.bg, hovered and Theme.color.accent or Theme.color.fill)
		else
			setColor(button.bg, hovered and Theme.color.buttonHover or Theme.color.button)
		end
	end

	local function newButton()
		local button = CreateFrame("Button", nil, frame)

		local bg = button:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		button.bg = bg

		local label = newText(button, Theme.size.value, Theme.color.text)
		label:SetPoint("LEFT", button, "LEFT", 12, 0)
		label:SetPoint("RIGHT", button, "RIGHT", -12, 0)
		label:SetWordWrap(false)
		button.label = label

		button:SetScript("OnEnter", function(self)
			self.hovered = true
			paint(self)
		end)
		button:SetScript("OnLeave", function(self)
			self.hovered = false
			paint(self)
		end)
		button:SetScript("OnClick", function(self)
			if self.func then
				self.func()
			end
		end)
		return button
	end

	local function configure(button, entry, primary)
		button.primary = primary
		button.func = entry.func
		button.label:SetText(entry.name)
		if entry.disabled then
			button:Disable()
			button:SetAlpha(Theme.disabledAlpha)
		else
			button:Enable()
			button:SetAlpha(1)
		end
		paint(button)
		button:Show()
	end

	local function place(region, y, height)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		return y + height
	end

	local function textHeight(fs)
		return math.ceil(fs:GetStringHeight())
	end

	local function build()
		frame = CreateFrame("Frame", W.FRAME, UIParent, "BackdropTemplate")
		frame:Hide()
		frame:SetWidth(WIDTH)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:SetBackdrop({ edgeFile = Theme.texture, edgeSize = 1 })
		local border = Theme.color.border
		frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])

		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		setColor(bg, Theme.color.bg)

		local header = CreateFrame("Frame", nil, frame)
		header:SetPoint("TOPLEFT")
		header:SetPoint("TOPRIGHT")
		header:SetHeight(HEADER)
		header:EnableMouse(true)
		header:SetScript("OnMouseDown", function(_, mouseButton)
			if mouseButton == "LeftButton" then
				frame:StartMoving()
			end
		end)
		header:SetScript("OnMouseUp", function()
			frame:StopMovingOrSizing()
		end)

		local headerBg = header:CreateTexture(nil, "BACKGROUND")
		headerBg:SetAllPoints()
		setColor(headerBg, Theme.color.header)

		local brand = newText(header, Theme.size.title, Theme.color.accent)
		brand:SetPoint("LEFT", header, "LEFT", PAD, 0)
		brand:SetText("MerrinxUI")

		title = newText(header, Theme.size.label, Theme.color.textDim)
		title:SetPoint("LEFT", brand, "RIGHT", 10, 0)

		local close = CreateFrame("Button", nil, header)
		close:SetSize(28, 28)
		close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
		local closeLabel = newText(close, Theme.size.title, Theme.color.text)
		closeLabel:SetAllPoints()
		closeLabel:SetJustifyH("CENTER")
		closeLabel:SetText("x")
		close.label = closeLabel
		close:SetScript("OnEnter", function()
			setTextColor(closeLabel, Theme.color.error)
		end)
		close:SetScript("OnLeave", function()
			setTextColor(closeLabel, Theme.color.text)
		end)
		close:SetScript("OnClick", function()
			window:Close()
		end)

		layerText = newText(frame, Theme.size.label, Theme.color.textDim)
		layerText:SetWidth(CONTENT_W)

		languageText = newText(frame, Theme.size.desc, Theme.color.textDim)
		languageText:SetWidth(CONTENT_W)

		statusCard = CreateFrame("Frame", nil, frame)
		statusCard:SetWidth(CONTENT_W)
		local cardBg = statusCard:CreateTexture(nil, "BACKGROUND")
		cardBg:SetAllPoints()
		setColor(cardBg, Theme.color.rowB)
		local cardBar = statusCard:CreateTexture(nil, "ARTWORK")
		cardBar:SetPoint("TOPLEFT")
		cardBar:SetPoint("BOTTOMLEFT")
		cardBar:SetWidth(Theme.geometry.activeBar)
		setColor(cardBar, Theme.color.accent)
		statusText = newText(statusCard, Theme.size.label, Theme.color.text)
		statusText:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 12, -8)
		statusText:SetWidth(CONTENT_W - 20)

		hopHeading = newText(frame, Theme.size.section, Theme.color.section)
		hopHeading:SetText("HOP TO")

		local footer = CreateFrame("Frame", nil, frame)
		footer:SetPoint("BOTTOMLEFT")
		footer:SetPoint("BOTTOMRIGHT")
		footer:SetHeight(FOOTER)
		local footerBg = footer:CreateTexture(nil, "BACKGROUND")
		footerBg:SetAllPoints()
		setColor(footerBg, Theme.color.header)
		statsText = newText(footer, Theme.size.desc, Theme.color.textDim)
		statsText:SetPoint("LEFT", footer, "LEFT", PAD, 0)

		if type(UISpecialFrames) == "table" then
			table.insert(UISpecialFrames, W.FRAME)
		end
	end

	local function render()
		local spec = W.Options(feature:WindowModel(), feature)
		local args = spec.args

		title:SetText(spec.name)
		layerText:SetText(args.layer.name)
		languageText:SetText(args.language.name)
		statusText:SetText(args.status.name)
		statsText:SetText(args.stats.name)

		local hops, actions = {}, {}
		for _, entry in pairs(args) do
			if entry.type == "execute" and not entry.hidden then
				local list = entry.width == "full" and hops or actions
				list[#list + 1] = entry
			end
		end
		table.sort(hops, byOrder)
		table.sort(actions, byOrder)

		local y = HEADER + PAD
		y = place(layerText, y, textHeight(layerText)) + 4
		y = place(languageText, y, textHeight(languageText)) + PAD
		local cardHeight = textHeight(statusText) + 16
		statusCard:SetHeight(cardHeight)
		y = place(statusCard, y, cardHeight) + PAD
		y = place(hopHeading, y, textHeight(hopHeading)) + GAP

		for i, entry in ipairs(hops) do
			local button = hopButtons[i] or newButton()
			hopButtons[i] = button
			button:SetSize(CONTENT_W, HOP_BUTTON)
			configure(button, entry, entry == args.any)
			y = place(button, y, HOP_BUTTON) + GAP
		end
		for i = #hops + 1, #hopButtons do
			hopButtons[i]:Hide()
		end
		y = y - GAP + PAD

		local x = PAD
		for i, entry in ipairs(actions) do
			local button = actionButtons[i] or newButton()
			actionButtons[i] = button
			configure(button, entry, false)
			local width = math.ceil(button.label:GetStringWidth()) + 24
			button:SetSize(width, ACTION_BUTTON)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
			x = x + width + GAP
		end
		for i = #actions + 1, #actionButtons do
			actionButtons[i]:Hide()
		end
		if #actions > 0 then
			y = y + ACTION_BUTTON + PAD
		end

		frame:SetHeight(y + FOOTER)
	end

	function window:Open()
		if not frame then
			build()
		end
		render()
		frame:Show()
		frame:Raise()
	end

	function window:Close()
		if frame then
			frame:Hide()
		end
	end

	function window:IsShown()
		return frame ~= nil and frame:IsShown() == true
	end

	function window:Refresh()
		if window:IsShown() then
			render()
		end
	end

	return window
end
