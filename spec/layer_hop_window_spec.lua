describe("LayerHopWindow", function()
	local addonName = "MerrinxUI_LayerHop"

	local function loadWindow()
		local ns = {}
		assert(loadfile("MerrinxUI_LayerHop/Theme.lua"))(addonName, ns)
		assert(loadfile("MerrinxUI_LayerHop/LayerHopWindow.lua"))(addonName, ns)
		return ns.LayerHopWindow
	end

	local function newFeature(model)
		local feature = { calls = {} }
		function feature:WindowModel()
			return model
		end
		function feature:HopTo(target)
			feature.calls.hopTo = target
		end
		function feature:CheckLayers()
			feature.calls.checkLayers = true
		end
		function feature:AskGeneralNow()
			feature.calls.askGeneralNow = true
		end
		function feature:Cancel()
			feature.calls.cancel = true
		end
		return feature
	end

	describe("Options", function()
		it("builds rows and hop buttons, hiding general and cancel while idle", function()
			local W = loadWindow()
			local row1Target = { kind = "layer", zone = 20 }
			local row2Target = { kind = "language", language = "French" }
			local model = {
				layerText = "layer text",
				languageText = "language text",
				status = "status text",
				rows = {
					{ label = "Layer 20: 1 answer", hosts = 1, target = row1Target },
					{ label = "French client, layer unknown: 1 answer", hosts = 1, target = row2Target },
				},
				busy = false,
				canAskGeneral = false,
				statsText = "stats text",
			}
			local feature = newFeature(model)

			local group = W.Options(model, feature)
			local args = group.args

			assert.are.equal("Layer Hop", group.name)
			assert.are.equal(model.rows[1].label, args.row1.name)
			assert.are.equal(model.rows[2].label, args.row2.name)

			args.row1.func()
			assert.are.equal(row1Target, feature.calls.hopTo)

			args.any.func()
			assert.are.equal("any", feature.calls.hopTo.kind)

			args.check.func()
			assert.is_true(feature.calls.checkLayers)

			assert.is_true(args.general.hidden)
			assert.is_true(args.cancel.hidden)

			assert.is_false(args.any.disabled)
			assert.is_false(args.row1.disabled)
			assert.is_false(args.row2.disabled)
			assert.is_false(args.check.disabled)
		end)

		it("disables hop buttons and shows cancel while busy", function()
			local W = loadWindow()
			local model = {
				layerText = "",
				languageText = "",
				status = "",
				rows = {
					{ label = "Layer 20: 1 answer", hosts = 1, target = { kind = "layer", zone = 20 } },
				},
				busy = true,
				canAskGeneral = false,
				statsText = "",
			}
			local feature = newFeature(model)

			local args = W.Options(model, feature).args

			assert.is_true(args.any.disabled)
			assert.is_true(args.row1.disabled)
			assert.is_true(args.check.disabled)
			assert.is_false(args.cancel.hidden)

			args.cancel.func()
			assert.is_true(feature.calls.cancel)
		end)

		it("shows Ask in General only when the model allows it", function()
			local W = loadWindow()
			local model = {
				layerText = "",
				languageText = "",
				status = "",
				rows = {},
				busy = false,
				canAskGeneral = true,
				statsText = "",
			}
			local feature = newFeature(model)

			local args = W.Options(model, feature).args

			assert.is_false(args.general.hidden)

			args.general.func()
			assert.is_true(feature.calls.askGeneralNow)
		end)
	end)

	describe("New", function()
		local saved = {}
		local created

		local function noop() end

		local methods = {}

		local function newObject(kind, parent)
			local o = { kind = kind, shown = true, enabled = true, scripts = {}, parent = parent }
			created[#created + 1] = o
			return setmetatable(o, {
				__index = function(_, k)
					return methods[k] or noop
				end,
			})
		end

		function methods:Show()
			self.shown = true
		end
		function methods:Hide()
			self.shown = false
		end
		function methods:IsShown()
			return self.shown
		end
		function methods:IsVisible()
			local o = self
			while o do
				if o.shown == false then
					return false
				end
				o = o.parent
			end
			return true
		end
		function methods:SetScript(name, fn)
			self.scripts[name] = fn
		end
		function methods:Enable()
			self.enabled = true
		end
		function methods:Disable()
			self.enabled = false
		end
		function methods:IsEnabled()
			return self.enabled
		end
		function methods:SetText(text)
			self.text = text
		end
		function methods:SetFont()
			return true
		end
		function methods:SetHeight(h)
			self.height = h
		end
		function methods:GetStringHeight()
			return 14
		end
		function methods:GetStringWidth()
			return 40
		end
		function methods:CreateTexture()
			return newObject("Texture", self)
		end
		function methods:CreateFontString()
			return newObject("FontString", self)
		end

		before_each(function()
			created = {}
			for _, name in ipairs({ "CreateFrame", "UIParent", "UISpecialFrames" }) do
				saved[name] = rawget(_G, name)
			end
			rawset(_G, "UIParent", {})
			rawset(_G, "UISpecialFrames", {})
			rawset(_G, "CreateFrame", function(kind, name, parent)
				local o = newObject(kind, parent)
				o.name = name
				return o
			end)
		end)

		after_each(function()
			for name, value in pairs(saved) do
				rawset(_G, name, value)
			end
		end)

		local function newModel()
			return {
				layerText = "layer text",
				languageText = "language text",
				status = "status text",
				rows = {
					{ label = "Layer 20: 1 answer", hosts = 1, target = { kind = "layer", zone = 20 } },
				},
				busy = false,
				canAskGeneral = false,
				statsText = "stats text",
			}
		end

		local function visibleButton(label)
			for _, o in ipairs(created) do
				if o.kind == "Button" and o.label and o.label.text == label and o:IsVisible() then
					return o
				end
			end
			return nil
		end

		local function frameNamed(name)
			for _, o in ipairs(created) do
				if o.name == name then
					return o
				end
			end
		end

		it("builds the frame once, registers it for Escape and renders the model", function()
			local W = loadWindow()
			local model = newModel()
			local feature = newFeature(model)
			local window = W.New(feature)

			assert.is_false(window:IsShown())
			window:Open()
			window:Open()

			local count = 0
			for _, o in ipairs(created) do
				if o.name == W.FRAME then
					count = count + 1
				end
			end
			assert.are.equal(1, count)
			assert.are.same({ W.FRAME }, UISpecialFrames)
			assert.is_true(window:IsShown())

			local texts = {}
			for _, o in ipairs(created) do
				if o.kind == "FontString" and o.text then
					texts[o.text] = true
				end
			end
			for _, text in ipairs({ "Layer Hop", "layer text", "language text", "status text", "stats text" }) do
				assert.is_true(texts[text], text)
			end

			assert.is_not_nil(visibleButton("Hop to any other layer"))
			assert.is_not_nil(visibleButton("Check again"))
			assert.is_nil(visibleButton("Ask in General"))
			assert.is_nil(visibleButton("Cancel"))

			local row = visibleButton("Layer 20: 1 answer")
			row.scripts.OnClick(row)
			assert.are.equal(model.rows[1].target, feature.calls.hopTo)

			local check = visibleButton("Check again")
			check.scripts.OnClick(check)
			assert.is_true(feature.calls.checkLayers)
		end)

		it("re-renders on Refresh only while shown and reflects busy state", function()
			local W = loadWindow()
			local model = newModel()
			local feature = newFeature(model)
			local window = W.New(feature)

			window:Refresh()
			assert.are.equal(0, #created)

			window:Open()
			model.busy = true
			model.rows = {}
			model.status = "busy now"
			window:Refresh()

			assert.is_nil(visibleButton("Layer 20: 1 answer"))
			assert.is_false(visibleButton("Hop to any other layer"):IsEnabled())
			assert.is_false(visibleButton("Check again"):IsEnabled())
			local cancel = visibleButton("Cancel")
			assert.is_true(cancel:IsEnabled())
			cancel.scripts.OnClick(cancel)
			assert.is_true(feature.calls.cancel)

			window:Close()
			assert.is_false(window:IsShown())
			assert.is_false(frameNamed(W.FRAME):IsShown())

			model.status = "hidden change"
			window:Refresh()
			for _, o in ipairs(created) do
				assert.are_not.equal("hidden change", o.text)
			end
		end)
	end)
end)
