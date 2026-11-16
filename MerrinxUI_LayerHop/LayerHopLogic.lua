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

function L.Encode(kind, id, map, zone, locale)
	if kind == "P" then
		return string.format("P|%d", id)
	end
	local text = string.format("%s|%d|%d|%d", kind, id, map or 0, zone or 0)
	if kind == "O" and type(locale) == "string" and locale:match("^%l%l%u%u$") then
		text = text .. "|" .. locale
	end
	return text
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
	local id, map, zone, locale = text:match("^O|(%d+)|(%d+)|(%d+)|(%l%l%u%u)$")
	local kind = id and "O" or nil
	if not kind then
		kind, id, map, zone = text:match("^([QO])|(%d+)|(%d+)|(%d+)$")
	end
	if not kind then
		return nil
	end
	id = positive(id, L.MAX_ID)
	-- An offer carries 0 for a map or layer its host does not know.
	if kind == "O" then
		map, zone = tonumber(map), tonumber(zone)
	else
		map, zone = positive(map), positive(zone)
	end
	if not (id and map and zone) then
		return nil
	end
	local msg = { kind = kind, id = id, map = map, zone = zone }
	if kind == "O" then
		msg.locale = locale
	end
	return msg
end

-- host: { hosting, grouped, instance, combat, map, zone }
-- Layer UIDs only compare within one map, so a host elsewhere cannot rule itself out.
function L.CanHost(host, request)
	if not host.hosting or host.grouped or host.instance or host.combat then
		return false
	end
	return host.map ~= request.map or host.zone ~= request.zone
end

-- true when the offer is on another layer, false when on the same one, nil when unknown.
function L.OtherLayer(request, offer)
	if offer.map ~= request.map or offer.zone == 0 then
		return nil
	end
	return offer.zone ~= request.zone
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

local LANGUAGE_NAMES = {
	enUS = "English",
	enGB = "English",
	deDE = "German",
	frFR = "French",
	esES = "Spanish",
	esMX = "Spanish",
	itIT = "Italian",
	ptBR = "Portuguese",
	ptPT = "Portuguese",
	ruRU = "Russian",
	koKR = "Korean",
	zhCN = "Chinese",
	zhTW = "Chinese",
}

-- Unmapped locale-shaped codes are returned as-is so same-locale clients still group together.
function L.Language(locale)
	if type(locale) ~= "string" then
		return nil
	end
	local name = LANGUAGE_NAMES[locale]
	if name then
		return name
	end
	if locale:match("^%l%l%u%u$") then
		return locale
	end
	return nil
end

function L.AddOffer(offers, offer, max)
	if #offers >= max then
		return false
	end
	for _, existing in ipairs(offers) do
		if L.SameName(existing.sender, offer.sender) then
			return false
		end
	end
	offers[#offers + 1] = offer
	return true
end

local function bySenderAsc(a, b)
	return a.sender < b.sender
end

function L.Choose(offers, request, target, myLanguage, rand)
	local ranks, sureFor

	if target.kind == "layer" then
		local candidates = {}
		if target.zone ~= request.zone then
			for _, offer in ipairs(offers) do
				if offer.map == request.map and offer.zone == target.zone then
					candidates[#candidates + 1] = offer
				end
			end
		end
		ranks, sureFor = { candidates }, { true }
	elseif target.kind == "language" then
		local confirmed, unknown = {}, {}
		for _, offer in ipairs(offers) do
			local other = L.OtherLayer(request, offer)
			if offer.language == target.language and other ~= false then
				if other == true then
					confirmed[#confirmed + 1] = offer
				else
					unknown[#unknown + 1] = offer
				end
			end
		end
		ranks, sureFor = { confirmed, unknown }, { true, true }
	else
		local confirmed, foreignUnknown, otherUnknown = {}, {}, {}
		for _, offer in ipairs(offers) do
			local other = L.OtherLayer(request, offer)
			if other ~= false then
				local foreign = myLanguage ~= nil and offer.language ~= nil and offer.language ~= myLanguage
				if other == true then
					confirmed[#confirmed + 1] = offer
				elseif foreign then
					foreignUnknown[#foreignUnknown + 1] = offer
				else
					otherUnknown[#otherUnknown + 1] = offer
				end
			end
		end
		ranks, sureFor = { confirmed, foreignUnknown, otherUnknown }, { true, false, false }
	end

	for i, candidates in ipairs(ranks) do
		if #candidates > 0 then
			table.sort(candidates, bySenderAsc)
			return candidates[rand(1, #candidates)].sender, sureFor[i]
		end
	end
	return nil, false
end

function L.Rows(offers, request, myLanguage)
	local byZone, zones = {}, {}
	local byLanguage, languages = {}, {}

	for _, offer in ipairs(offers) do
		if offer.map == request.map and offer.zone ~= 0 and offer.zone ~= request.zone then
			local group = byZone[offer.zone]
			if not group then
				group = {}
				byZone[offer.zone] = group
				zones[#zones + 1] = offer.zone
			end
			group[#group + 1] = offer
		end
		local foreign = myLanguage ~= nil and offer.language ~= nil and offer.language ~= myLanguage
		if foreign and L.OtherLayer(request, offer) == nil then
			local group = byLanguage[offer.language]
			if not group then
				group = {}
				byLanguage[offer.language] = group
				languages[#languages + 1] = offer.language
			end
			group[#group + 1] = offer
		end
	end

	table.sort(zones)
	table.sort(languages)

	local rows = {}
	for _, zone in ipairs(zones) do
		local group = byZone[zone]
		local n = #group
		local seen, known = {}, {}
		for _, offer in ipairs(group) do
			if offer.language and not seen[offer.language] then
				seen[offer.language] = true
				known[#known + 1] = offer.language
			end
		end
		table.sort(known)
		local label = string.format("Layer %d: %d %s", zone, n, n == 1 and "answer" or "answers")
		if #known > 0 then
			label = label .. " (" .. table.concat(known, ", ") .. ")"
		end
		rows[#rows + 1] = { label = label, hosts = n, target = { kind = "layer", zone = zone } }
	end

	for _, language in ipairs(languages) do
		local n = #byLanguage[language]
		local label = string.format("%s client, layer unknown: %d %s", language, n, n == 1 and "answer" or "answers")
		rows[#rows + 1] = { label = label, hosts = n, target = { kind = "language", language = language } }
	end

	return rows
end
