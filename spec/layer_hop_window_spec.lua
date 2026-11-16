describe("LayerHopWindow", function()
	local addonName = "MerrinxUI_LayerHop"
	local realLibStub

	before_each(function()
		realLibStub = rawget(_G, "LibStub")
	end)

	after_each(function()
		rawset(_G, "LibStub", realLibStub)
	end)

	local function loadWindow()
		local ns = {}
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
		local function newLibs()
			local registerCalls = {}
			local sizeCalls = {}
			local openCalls = {}
			local closeCalls = {}
			local notifyCalls = {}
			local openFrames = {}

			local libs = {
				["AceConfig-3.0"] = {
					RegisterOptionsTable = function(_, name, fn)
						registerCalls[#registerCalls + 1] = { name = name, fn = fn }
					end,
				},
				["AceConfigDialog-3.0"] = {
					SetDefaultSize = function(_, name, width, height)
						sizeCalls[#sizeCalls + 1] = { name = name, width = width, height = height }
					end,
					Open = function(_, name)
						openCalls[#openCalls + 1] = name
						openFrames[name] = true
					end,
					Close = function(_, name)
						closeCalls[#closeCalls + 1] = name
						openFrames[name] = nil
					end,
					OpenFrames = openFrames,
				},
				["AceConfigRegistry-3.0"] = {
					NotifyChange = function(_, name)
						notifyCalls[#notifyCalls + 1] = name
					end,
				},
			}
			rawset(_G, "LibStub", function(major)
				return libs[major]
			end)

			return {
				registerCalls = registerCalls,
				sizeCalls = sizeCalls,
				openCalls = openCalls,
				closeCalls = closeCalls,
				notifyCalls = notifyCalls,
				openFrames = openFrames,
			}
		end

		it("registers and sizes once, opens every call, with a live options function", function()
			local W = loadWindow()
			local libs = newLibs()
			local model = {
				layerText = "layer text",
				languageText = "",
				status = "",
				rows = {},
				busy = false,
				canAskGeneral = false,
				statsText = "",
			}
			local feature = newFeature(model)
			local window = W.New(feature)

			window:Open()
			window:Open()

			assert.are.equal(1, #libs.registerCalls)
			assert.are.equal(W.APP, libs.registerCalls[1].name)
			assert.are.equal(1, #libs.sizeCalls)
			assert.are.same({ name = W.APP, width = 440, height = 420 }, libs.sizeCalls[1])
			assert.are.equal(2, #libs.openCalls)
			assert.are.equal(W.APP, libs.openCalls[1])

			local result = libs.registerCalls[1].fn()
			assert.are.equal(model.layerText, result.args.layer.name)

			model.layerText = "changed"
			local updated = libs.registerCalls[1].fn()
			assert.are.equal("changed", updated.args.layer.name)
		end)

		it("tracks IsShown from OpenFrames and only refreshes when shown", function()
			local W = loadWindow()
			local libs = newLibs()
			local model = {
				layerText = "",
				languageText = "",
				status = "",
				rows = {},
				busy = false,
				canAskGeneral = false,
				statsText = "",
			}
			local feature = newFeature(model)
			local window = W.New(feature)

			assert.is_false(window:IsShown())
			window:Refresh()
			assert.are.equal(0, #libs.notifyCalls)

			window:Open()
			assert.is_true(window:IsShown())
			window:Refresh()
			assert.are.equal(1, #libs.notifyCalls)
			assert.are.equal(W.APP, libs.notifyCalls[1])

			window:Close()
			assert.are.equal(W.APP, libs.closeCalls[1])
			assert.is_false(window:IsShown())
		end)
	end)
end)
