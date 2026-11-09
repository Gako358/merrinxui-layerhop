local addonName, ns = ...

local LayerHopLogic = {}
ns.LayerHopLogic = LayerHopLogic

local L = LayerHopLogic

L.PREFIX = "MUIHop1"
L.MAX_ID = 999999
L.MAX_LENGTH = 64

-- Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>; the zoneUID differs per layer.
function L.ParseGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, zone = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-%d+%-%x+$")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	zone = tonumber(zone)
	if not zone or zone == 0 then
		return nil
	end
	return zone
end

function L.NewLayer()
	return {}
end

-- A layer only counts once two different NPCs agree, so a single creature seen across a
-- layer border cannot flip it.
function L.Observe(state, map, zone, guid)
	if state.map ~= map then
		state.map, state.zone, state.pending = map, nil, nil
	end
	if state.zone == zone then
		state.pending = nil
		return false
	end
	local pending = state.pending
	if pending and pending.zone == zone then
		if pending.guid ~= guid then
			state.zone, state.pending = zone, nil
			return true
		end
		return false
	end
	state.pending = { zone = zone, guid = guid }
	return false
end

function L.Current(state, map)
	if map ~= nil and state.map == map then
		return state.zone
	end
	return nil
end

function L.Encode(kind, id, map, zone)
	if kind == "P" then
		return string.format("P|%d", id)
	end
	return string.format("%s|%d|%d|%d", kind, id, map, zone)
end

local function positive(text, max)
	local n = tonumber(text)
	if not n or n < 1 or n % 1 ~= 0 or (max and n > max) then
		return nil
	end
	return n
end

function L.Decode(text)
	if type(text) ~= "string" or #text > L.MAX_LENGTH then
		return nil
	end
	local pick = text:match("^P|(%d+)$")
	if pick then
		local id = positive(pick, L.MAX_ID)
		return id and { kind = "P", id = id } or nil
	end
	local kind, id, map, zone = text:match("^([QO])|(%d+)|(%d+)|(%d+)$")
	if not kind then
		return nil
	end
	id, map, zone = positive(id, L.MAX_ID), positive(map), positive(zone)
	if not (id and map and zone) then
		return nil
	end
	return { kind = kind, id = id, map = map, zone = zone }
end

-- host: { hosting, grouped, instance, combat, map, zone }
function L.CanHost(host, request)
	if not host.hosting or host.grouped or host.instance or host.combat then
		return false
	end
	return host.zone ~= nil and host.map == request.map and host.zone ~= request.zone
end

function L.ShortName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return (name:match("^[^%-]+") or name):lower()
end

function L.SameName(a, b)
	local short = L.ShortName(a)
	return short ~= nil and short == L.ShortName(b)
end

function L.AcceptsInvite(hop, inviter)
	if not hop or L.ShortName(inviter) == nil then
		return false
	end
	if hop.state == "public" then
		return true
	end
	return hop.state == "picked" and L.SameName(inviter, hop.host)
end

-- rand(m, n) returns an integer in [m, n], like math.random.
function L.Sample(names, n, rand, skip)
	local pool = {}
	for _, name in ipairs(names) do
		if not skip(name) then
			pool[#pool + 1] = name
		end
	end
	local count = math.min(n, #pool)
	for i = 1, count do
		local j = rand(i, #pool)
		pool[i], pool[j] = pool[j], pool[i]
	end
	for i = #pool, count + 1, -1 do
		pool[i] = nil
	end
	return pool
end

function L.Prune(offers, now, ttl)
	local count = 0
	for id, offer in pairs(offers) do
		if now - offer.at > ttl then
			offers[id] = nil
		else
			count = count + 1
		end
	end
	return count
end
