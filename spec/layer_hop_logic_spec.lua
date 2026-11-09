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

		it("does not host the same layer, another map or an unknown layer", function()
			request.zone = 20
			assert.is_false(L.CanHost(host, request))
			request.zone, request.map = 10, 1433
			assert.is_false(L.CanHost(host, request))
			request.map, host.zone = 1429, nil
			assert.is_false(L.CanHost(host, request))
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
