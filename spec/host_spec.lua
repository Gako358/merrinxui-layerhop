local function noop() end

describe("Host", function()
	local addonName = "MerrinxUI_LayerHop"
	local realLibStub, realPrint

	before_each(function()
		realLibStub = rawget(_G, "LibStub")
		realPrint = rawget(_G, "print")
	end)

	after_each(function()
		rawset(_G, "LibStub", realLibStub)
		rawset(_G, "print", realPrint)
	end)

	local function newAceAddonObj(name)
		local obj = { name = name }
		function obj:Print(text)
			obj.printed = text
		end
		function obj:RegisterChatCommand(cmd, handler)
			obj.chatCommand = cmd
			obj.chatHandler = handler
		end
		function obj:RegisterSlash(verb, handler)
			obj.slashVerb = verb
			obj.slashHandler = handler
		end
		function obj:NewModule(moduleName)
			local mod = newAceAddonObj(name .. "_" .. moduleName)
			obj.module = mod
			return mod
		end
		return obj
	end

	local function newEnv(opts)
		opts = opts or {}

		local printed = {}
		rawset(_G, "print", function(text)
			printed[#printed + 1] = text
		end)

		local addons = {}
		local aceAddon = {}
		function aceAddon:GetAddon(name)
			return addons[name]
		end
		function aceAddon:NewAddon(name)
			local obj = newAceAddonObj(name)
			addons[name] = obj
			return obj
		end

		if opts.inert then
			addons[addonName] = newAceAddonObj(addonName)
		end

		local host
		if opts.host then
			host = newAceAddonObj("MerrinxUI")
			addons["MerrinxUI"] = host
			host.db = {}
			function host.db:RegisterNamespace(name, defaults)
				host.namespace = { name = name, defaults = defaults }
				return { profile = defaults.profile or {} }
			end
			if opts.api ~= false then
				local api = opts.api
					or {
						Debug = { Log = noop, RegisterChecks = noop },
						OptionsWindow = {
							CurrentPage = function()
								return opts.page
							end,
							CurrentTab = function()
								return opts.tab
							end,
						},
					}
				host.GetPluginAPI = function(_, version)
					if version == 1 then
						return api
					end
					return nil
				end
			end
		end

		local aceDBCalls = {}
		local notifyCalls = {}
		local configCalls = {}
		local dialogCalls = {}

		local libs = {
			["AceAddon-3.0"] = aceAddon,
			["AceDB-3.0"] = {
				New = function(_, sv, defaults, defaultProfile)
					aceDBCalls[#aceDBCalls + 1] = { sv = sv, defaults = defaults, defaultProfile = defaultProfile }
					return { profile = defaults.profile or {} }
				end,
			},
			["AceConfigRegistry-3.0"] = {
				NotifyChange = function(_, name)
					notifyCalls[#notifyCalls + 1] = name
				end,
			},
			["AceConfig-3.0"] = {
				RegisterOptionsTable = function(_, name, fn)
					configCalls[#configCalls + 1] = { name = name, fn = fn }
				end,
			},
			["AceConfigDialog-3.0"] = {
				Open = function(_, name)
					dialogCalls[#dialogCalls + 1] = name
				end,
			},
		}

		rawset(_G, "LibStub", function(major)
			return libs[major]
		end)

		return {
			printed = printed,
			addons = addons,
			host = host,
			aceDBCalls = aceDBCalls,
			notifyCalls = notifyCalls,
			configCalls = configCalls,
			dialogCalls = dialogCalls,
		}
	end

	local function loadHost()
		local ns = {}
		assert(loadfile("MerrinxUI_LayerHop/Host.lua"))(addonName, ns)
		return ns
	end

	describe("standalone", function()
		it("creates a standalone addon and chat command when there is no host", function()
			local env = newEnv({})
			local ns = loadHost()

			assert.is_false(ns.inert)
			assert.is_false(ns.integrated)
			assert.are.equal(addonName, ns.appName)
			assert.are.equal("/layerhop", ns.slashHint)
			assert.are.equal("/layerhop config", ns.optionsHint)

			local obj = ns.NewFeature("LayerHop", "AceEvent-3.0")
			assert.are.equal(env.addons[addonName], obj)
			assert.are.equal("layerhop", obj.chatCommand)
			assert.is_function(obj.chatHandler)

			ns.NewDB("LayerHop", { profile = { enabled = true } })
			assert.are.equal(1, #env.aceDBCalls)
			assert.are.equal("MerrinxUI_LayerHopDB", env.aceDBCalls[1].sv)
			assert.is_true(env.aceDBCalls[1].defaultProfile)
		end)
	end)

	describe("integrated", function()
		it("registers as a module and dispatches the slash through the host", function()
			local env = newEnv({ host = true })
			local ns = loadHost()

			assert.is_false(ns.inert)
			assert.is_true(ns.integrated)
			assert.are.equal("MerrinxUI", ns.appName)
			assert.are.equal("/mui hop", ns.slashHint)
			assert.are.equal("/mui > QoL > Layer Hop", ns.optionsHint)

			local obj = ns.NewFeature("LayerHop", "AceEvent-3.0")
			assert.are.equal(env.host.module, obj)
			assert.are.equal("hop", env.host.slashVerb)

			local hopped = false
			obj.Hop = function()
				hopped = true
			end
			env.host.slashHandler()
			assert.is_true(hopped)

			ns.NewDB("LayerHop", { profile = {} })
			assert.are.equal("LayerHop", env.host.namespace.name)
		end)
	end)

	describe("integrated fallback", function()
		it("is standalone when the host has no GetPluginAPI function", function()
			local env = newEnv({ host = true, api = false })
			local ns = loadHost()
			assert.is_false(ns.integrated)
			assert.is_nil(env.host.GetPluginAPI)
		end)

		it("is standalone when GetPluginAPI(1) returns nil", function()
			local env = newEnv({ host = true })
			env.host.GetPluginAPI = function()
				return nil
			end
			local ns = loadHost()
			assert.is_false(ns.integrated)
		end)
	end)

	describe("inert", function()
		it("sets ns.inert and prints the message once", function()
			local env = newEnv({ inert = true })
			local ns = loadHost()

			assert.is_true(ns.inert)
			assert.is_false(ns.integrated)
			assert.are.equal(1, #env.printed)
			assert.is_not_nil(env.printed[1]:find(addonName, 1, true))
		end)
	end)

	describe("NotifyOptions", function()
		it("does not notify when neither the current page nor tab match", function()
			local env = newEnv({ host = true, page = "Other", tab = "Other" })
			local ns = loadHost()
			ns.NotifyOptions("Layer Hop")
			assert.are.equal(0, #env.notifyCalls)
		end)

		it("notifies MerrinxUI when the current tab matches", function()
			local env = newEnv({ host = true, tab = "Layer Hop" })
			local ns = loadHost()
			ns.NotifyOptions("Layer Hop")
			assert.are.equal(1, #env.notifyCalls)
			assert.are.equal("MerrinxUI", env.notifyCalls[1])
		end)

		it("notifies MerrinxUI when the current page matches", function()
			local env = newEnv({ host = true, page = "Layer Hop" })
			local ns = loadHost()
			ns.NotifyOptions("Layer Hop")
			assert.are.equal(1, #env.notifyCalls)
			assert.are.equal("MerrinxUI", env.notifyCalls[1])
		end)

		it("notifies the addon name in standalone mode", function()
			local env = newEnv({})
			local ns = loadHost()
			ns.NotifyOptions("Layer Hop")
			assert.are.equal(1, #env.notifyCalls)
			assert.are.equal(addonName, env.notifyCalls[1])
		end)
	end)

	describe("standalone slash handler", function()
		it("opens the options on config and calls Hop otherwise", function()
			local env = newEnv({})
			local ns = loadHost()
			local obj = ns.NewFeature("LayerHop", "AceEvent-3.0")
			local hopped = false
			obj.Hop = function()
				hopped = true
			end

			obj.chatHandler(" Config ")
			assert.are.equal(1, #env.configCalls)
			assert.are.equal(addonName, env.configCalls[1].name)
			assert.are.equal(1, #env.dialogCalls)
			assert.are.equal(addonName, env.dialogCalls[1])
			assert.is_false(hopped)

			obj.chatHandler("")
			assert.is_true(hopped)
		end)
	end)
end)
