describe("LayerHopLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI_LayerHop/LayerHopLogic.lua"))("MerrinxUI_LayerHop", ns)
		L = ns.LayerHopLogic
	end)

	describe("ParseGUID", function()
		it("reads the zone UID of a creature or vehicle", function()
			assert.are.equal(4567, L.ParseGUID("Creature-0-5250-0-4567-299-0000A1B2C3"))
			assert.are.equal(12, L.ParseGUID("Vehicle-0-5250-0-12-299-0000A1B2C3"))
		end)

		it("ignores players, pets, a zero zone and anything malformed", function()
			assert.is_nil(L.ParseGUID("Player-5250-0A1B2C3D"))
			assert.is_nil(L.ParseGUID("Pet-0-5250-0-4567-299-0000A1B2C3"))
			assert.is_nil(L.ParseGUID("Creature-0-5250-0-0-299-0000A1B2C3"))
			assert.is_nil(L.ParseGUID("Creature-0-5250-0-4567"))
			assert.is_nil(L.ParseGUID(nil))
		end)
	end)

	describe("Observe", function()
		it("takes a layer only once two different NPCs report it", function()
			local s = L.NewLayer()
			assert.is_false(L.Observe(s, 1429, 10, "a"))
			assert.is_nil(L.Current(s, 1429))
			assert.is_false(L.Observe(s, 1429, 10, "a"))
			assert.is_true(L.Observe(s, 1429, 10, "b"))
			assert.are.equal(10, L.Current(s, 1429))
		end)

		it("keeps the layer when one NPC from another layer shows up", function()
			local s = L.NewLayer()
			L.Observe(s, 1429, 10, "a")
			L.Observe(s, 1429, 10, "b")
			assert.is_false(L.Observe(s, 1429, 20, "c"))
			assert.is_false(L.Observe(s, 1429, 10, "d"))
			assert.is_false(L.Observe(s, 1429, 20, "e"))
			assert.are.equal(10, L.Current(s, 1429))
			assert.is_true(L.Observe(s, 1429, 20, "f"))
			assert.are.equal(20, L.Current(s, 1429))
		end)

		it("forgets the layer on another map", function()
			local s = L.NewLayer()
			L.Observe(s, 1429, 10, "a")
			L.Observe(s, 1429, 10, "b")
			assert.is_nil(L.Current(s, 1433))
			assert.is_nil(L.Current(s, nil))
			assert.is_false(L.Observe(s, 1433, 30, "c"))
			assert.is_nil(L.Current(s, 1429))
		end)
	end)

	describe("Encode and Decode", function()
		it("round-trips queries, offers and picks", function()
			assert.are.same({ kind = "Q", id = 42, map = 1429, zone = 10 }, L.Decode(L.Encode("Q", 42, 1429, 10)))
			assert.are.same({ kind = "O", id = 42, map = 1429, zone = 20 }, L.Decode(L.Encode("O", 42, 1429, 20)))
			assert.are.same({ kind = "P", id = 42 }, L.Decode(L.Encode("P", 42)))
		end)

		it("sends an unknown map or layer of an offer as 0", function()
			assert.are.equal("O|42|1433|0", L.Encode("O", 42, 1433, nil))
			assert.are.same({ kind = "O", id = 42, map = 0, zone = 0 }, L.Decode(L.Encode("O", 42, nil, nil)))
			assert.is_nil(L.Decode("Q|42|1429|0"))
		end)

		it("rejects unknown kinds, bad numbers, extra fields and long text", function()
			assert.is_nil(L.Decode("X|1|2|3"))
			assert.is_nil(L.Decode("Q|0|2|3"))
			assert.is_nil(L.Decode("Q|1|0|3"))
			assert.is_nil(L.Decode("Q|1000000|2|3"))
			assert.is_nil(L.Decode("Q|1|2|3|4"))
			assert.is_nil(L.Decode("Q|1|2"))
			assert.is_nil(L.Decode("P|"))
			assert.is_nil(L.Decode("P|1|2"))
			assert.is_nil(L.Decode("Q|1|2|" .. string.rep("9", 80)))
			assert.is_nil(L.Decode(nil))
		end)

		it("keeps the prefix for 1.0.1 interop", function()
			assert.are.equal("MUIHop1", L.PREFIX)
		end)

		it("appends a locale to an offer only when it matches the locale shape", function()
			assert.are.equal("O|42|1429|20|frFR", L.Encode("O", 42, 1429, 20, "frFR"))
			assert.are.equal("O|42|1429|20", L.Encode("O", 42, 1429, 20, "bad"))
			assert.are.equal("Q|42|1429|10", L.Encode("Q", 42, 1429, 10, "frFR"))
		end)

		it("decodes a 5-field offer locale and keeps 4-field offers without a locale key", function()
			assert.are.same(
				{ kind = "O", id = 42, map = 1429, zone = 20, locale = "frFR" },
				L.Decode("O|42|1429|20|frFR")
			)
			assert.are.same({ kind = "O", id = 42, map = 0, zone = 0, locale = "deDE" }, L.Decode("O|42|0|0|deDE"))
		end)

		it("rejects a malformed or extra locale field and a locale on a query", function()
			assert.is_nil(L.Decode("O|42|1429|20|fr"))
			assert.is_nil(L.Decode("O|42|1429|20|FRFR"))
			assert.is_nil(L.Decode("O|42|1429|20|frFR|x"))
			assert.is_nil(L.Decode("Q|1|2|3|frFR"))
		end)
	end)

	describe("Language", function()
		it("maps known locales to a language name", function()
			assert.are.equal("English", L.Language("enUS"))
			assert.are.equal("English", L.Language("enGB"))
			assert.are.equal("French", L.Language("frFR"))
			assert.are.equal("Spanish", L.Language("esMX"))
			assert.are.equal("German", L.Language("deDE"))
		end)

		it("returns an unmapped locale-shaped code as itself", function()
			assert.are.equal("xxYY", L.Language("xxYY"))
		end)

		it("returns nil for nil or malformed locales", function()
			assert.is_nil(L.Language(nil))
			assert.is_nil(L.Language("french"))
			assert.is_nil(L.Language(""))
		end)
	end)

	describe("AddOffer", function()
		it("appends to an empty list", function()
			local offers = {}
			assert.is_true(L.AddOffer(offers, { sender = "A" }, 40))
			assert.are.equal(1, #offers)
		end)

		it("rejects a duplicate sender by short name", function()
			local offers = { { sender = "A-Realm" } }
			assert.is_false(L.AddOffer(offers, { sender = "a" }, 40))
		end)

		it("rejects once the list is at max", function()
			local offers = { { sender = "A" }, { sender = "B" } }
			assert.is_false(L.AddOffer(offers, { sender = "C" }, 2))
		end)
	end)

	describe("Choose", function()
		local req = { map = 1429, zone = 10 }
		local me = "English"
		local first = function(m)
			return m
		end
		local last = function(_, n)
			return n
		end
		local A, B, C, D, E, F, G

		before_each(function()
			A = { sender = "A", map = 1429, zone = 20, language = "English" }
			B = { sender = "B", map = 1429, zone = 20, language = "French" }
			C = { sender = "C", map = 1429, zone = 30, language = nil }
			D = { sender = "D", map = 1433, zone = 99, language = "French" }
			E = { sender = "E", map = 1429, zone = 0, language = "German" }
			F = { sender = "F", map = 1433, zone = 5, language = "English" }
			G = { sender = "G", map = 1429, zone = 10, language = "French" }
		end)

		it("picks a confirmed host on the requested layer", function()
			local sender, sure = L.Choose({ A, B, C, D, E, F, G }, req, { kind = "layer", zone = 20 }, me, first)
			assert.are.equal("A", sender)
			assert.is_true(sure)
		end)

		it("refuses a layer target matching the requester's own layer", function()
			local sender, sure = L.Choose({ A, B, C, D, E, F, G }, req, { kind = "layer", zone = 10 }, me, first)
			assert.is_nil(sender)
			assert.is_false(sure)
		end)

		it("picks a confirmed host of the requested language", function()
			local sender, sure = L.Choose(
				{ A, B, C, D, E, F, G },
				req,
				{ kind = "language", language = "French" },
				me,
				first
			)
			assert.are.equal("B", sender)
			assert.is_true(sure)
		end)

		it("picks an unknown-layer host of the requested language", function()
			local sender, sure = L.Choose(
				{ A, B, C, D, E, F, G },
				req,
				{ kind = "language", language = "German" },
				me,
				first
			)
			assert.are.equal("E", sender)
			assert.is_true(sure)
		end)

		it("finds nobody for a language with no matching offer", function()
			local sender, sure = L.Choose(
				{ A, B, C, D, E, F, G },
				req,
				{ kind = "language", language = "Italian" },
				me,
				first
			)
			assert.is_nil(sender)
			assert.is_false(sure)
		end)

		it("picks a confirmed host first for any target", function()
			local sender, sure = L.Choose({ A, B, C, D, E, F, G }, req, { kind = "any" }, me, first)
			assert.are.equal("A", sender)
			assert.is_true(sure)
		end)

		it("uses rand across the whole confirmed rank", function()
			local sender, sure = L.Choose({ A, B, C, D, E, F, G }, req, { kind = "any" }, me, last)
			assert.are.equal("C", sender)
			assert.is_true(sure)
		end)

		it("falls back to a foreign-language unknown-layer host", function()
			local sender, sure = L.Choose({ D, F }, req, { kind = "any" }, me, first)
			assert.are.equal("D", sender)
			assert.is_false(sure)
		end)

		it("treats every unknown-layer host as foreign when the client language is unknown", function()
			local sender, sure = L.Choose({ D, F }, req, { kind = "any" }, nil, first)
			assert.are.equal("D", sender)
			assert.is_false(sure)
		end)

		it("falls back to an unknown-layer host of the same language", function()
			local sender, sure = L.Choose({ F }, req, { kind = "any" }, me, first)
			assert.are.equal("F", sender)
			assert.is_false(sure)
		end)

		it("excludes a confirmed same-layer host from any target", function()
			local sender, sure = L.Choose({ G }, req, { kind = "any" }, me, first)
			assert.is_nil(sender)
			assert.is_false(sure)
		end)

		it("finds nobody with no offers", function()
			local sender, sure = L.Choose({}, req, { kind = "any" }, me, first)
			assert.is_nil(sender)
			assert.is_false(sure)
		end)

		it("calls rand exactly once when a sender is returned", function()
			local calls = 0
			local rand = function(m, _)
				calls = calls + 1
				return m
			end
			L.Choose({ A, B, C, D, E, F, G }, req, { kind = "any" }, me, rand)
			assert.are.equal(1, calls)
		end)
	end)

	describe("Rows", function()
		local req = { map = 1429, zone = 10 }
		local me = "English"
		local A, B, C, D, E, F, G

		before_each(function()
			A = { sender = "A", map = 1429, zone = 20, language = "English" }
			B = { sender = "B", map = 1429, zone = 20, language = "French" }
			C = { sender = "C", map = 1429, zone = 30, language = nil }
			D = { sender = "D", map = 1433, zone = 99, language = "French" }
			E = { sender = "E", map = 1429, zone = 0, language = "German" }
			F = { sender = "F", map = 1433, zone = 5, language = "English" }
			G = { sender = "G", map = 1429, zone = 10, language = "French" }
		end)

		it("lists layer rows then foreign-language unknown-layer rows", function()
			local rows = L.Rows({ A, B, C, D, E, F, G }, req, me)
			assert.are.same({
				{
					label = "Layer 20: 2 answers (English, French)",
					hosts = 2,
					target = { kind = "layer", zone = 20 },
				},
				{ label = "Layer 30: 1 answer", hosts = 1, target = { kind = "layer", zone = 30 } },
				{
					label = "French client, layer unknown: 1 answer",
					hosts = 1,
					target = { kind = "language", language = "French" },
				},
				{
					label = "German client, layer unknown: 1 answer",
					hosts = 1,
					target = { kind = "language", language = "German" },
				},
			}, rows)
		end)

		it("omits language rows when the client language is unknown", function()
			local rows = L.Rows({ A, B, C, D, E, F, G }, req, nil)
			assert.are.same({
				{
					label = "Layer 20: 2 answers (English, French)",
					hosts = 2,
					target = { kind = "layer", zone = 20 },
				},
				{ label = "Layer 30: 1 answer", hosts = 1, target = { kind = "layer", zone = 30 } },
			}, rows)
		end)

		it("returns no rows with no offers", function()
			assert.are.same({}, L.Rows({}, req, me))
		end)
	end)

	describe("CanHost", function()
		local host, request

		before_each(function()
			host = { hosting = true, grouped = false, instance = false, combat = false, map = 1429, zone = 20 }
			request = { map = 1429, zone = 10 }
		end)

		it("hosts a request from another layer of the same map", function()
			assert.is_true(L.CanHost(host, request))
		end)

		it("does not host the same layer of the same map", function()
			request.zone = 20
			assert.is_false(L.CanHost(host, request))
		end)

		it("hosts from another map or an unknown layer or map", function()
			request.map = 1433
			assert.is_true(L.CanHost(host, request))
			request.map, host.zone = 1429, nil
			assert.is_true(L.CanHost(host, request))
			host.map = nil
			assert.is_true(L.CanHost(host, request))
		end)

		it("does not host when off, grouped, in an instance or in combat", function()
			for _, key in ipairs({ "grouped", "instance", "combat" }) do
				host[key] = true
				assert.is_false(L.CanHost(host, request), key)
				host[key] = false
			end
			host.hosting = false
			assert.is_false(L.CanHost(host, request))
		end)
	end)

	describe("OtherLayer", function()
		local request = { map = 1429, zone = 10 }

		it("confirms another layer only on the same map", function()
			assert.is_true(L.OtherLayer(request, { map = 1429, zone = 20 }))
			assert.is_false(L.OtherLayer(request, { map = 1429, zone = 10 }))
		end)

		it("cannot tell for another map or an unknown layer", function()
			assert.is_nil(L.OtherLayer(request, { map = 1433, zone = 20 }))
			assert.is_nil(L.OtherLayer(request, { map = 1429, zone = 0 }))
			assert.is_nil(L.OtherLayer(request, { map = 0, zone = 0 }))
		end)
	end)

	describe("SameName", function()
		it("compares names without realm and case", function()
			assert.is_true(L.SameName("Merrinx-Realm", "merrinx"))
			assert.is_true(L.SameName("Merrinx", "Merrinx"))
			assert.is_false(L.SameName("Merrinx", "Other"))
			assert.is_false(L.SameName(nil, nil))
			assert.is_false(L.SameName("", ""))
		end)
	end)

	describe("AcceptsInvite", function()
		it("accepts only the picked host while waiting on a MerrinxUI user", function()
			local hop = { state = "picked", host = "Helper-Realm" }
			assert.is_true(L.AcceptsInvite(hop, "helper"))
			assert.is_false(L.AcceptsInvite(hop, "Stranger"))
		end)

		it("accepts anyone after asking in General", function()
			assert.is_true(L.AcceptsInvite({ state = "public" }, "Stranger"))
			assert.is_false(L.AcceptsInvite({ state = "public" }, ""))
			assert.is_false(L.AcceptsInvite({ state = "public" }, nil))
		end)

		it("accepts nothing while idle, asking or already joining", function()
			assert.is_false(L.AcceptsInvite(nil, "Helper"))
			for _, state in ipairs({ "asking", "accepted", "joined" }) do
				assert.is_false(L.AcceptsInvite({ state = state, host = "Helper" }, "Helper"), state)
			end
		end)
	end)

	describe("Sample", function()
		it("picks up to n names, never a skipped one", function()
			local first = function(m)
				return m
			end
			local skip = function(name)
				return name == "me"
			end
			assert.are.same({ "a", "b" }, L.Sample({ "a", "me", "b", "c" }, 2, first, skip))
			assert.are.same({ "a", "b", "c" }, L.Sample({ "a", "me", "b", "c" }, 8, first, skip))
			assert.are.same({}, L.Sample({ "me" }, 8, first, skip))
		end)

		it("uses rand to choose", function()
			local last = function(_, n)
				return n
			end
			local none = function()
				return false
			end
			assert.are.same({ "c" }, L.Sample({ "a", "b", "c" }, 1, last, none))
		end)
	end)

	describe("Prune", function()
		it("drops offers older than ttl and counts the rest", function()
			local offers = { [1] = { at = 0 }, [2] = { at = 25 }, [3] = { at = 31 } }
			assert.are.equal(2, L.Prune(offers, 40, 30))
			assert.is_nil(offers[1])
			assert.is_not_nil(offers[2])
		end)
	end)
end)
