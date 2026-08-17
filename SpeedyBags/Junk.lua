local _, ns = ...

-- Reads Leatrix_Plus's own "Sell junk automatically" configuration so
-- SpeedyBags' Junk slot agrees with what Leatrix_Plus will actually sell
-- at the next vendor visit, instead of inventing a second, possibly-
-- conflicting definition of "junk". This is a soft, optional integration,
-- never a hard dependency -- falls back to Blizzard's own bare rule (Poor
-- quality + sellable) if Leatrix_Plus isn't installed/loaded. Working
-- WITH a complementary QoL addon like this is explicitly fine per the
-- user's own framing: the "no external dependencies" rule is about not
-- depending on other BAG addons or Syndicator (things this project exists
-- to do differently), not a blanket rule against any addon integration.
--
-- Verified directly against Leatrix_Plus's real source
-- (Interface/AddOns/Leatrix_Plus/Leatrix_Plus.lua on this machine, not
-- guessed): `_G.LeaPlusDB` is its real SavedVariables global (declared in
-- Leatrix_Plus.toc, account-wide, no per-character scoping), synced from
-- its internal `LeaPlusLC` config table on save (Leatrix_Plus.lua:10591-
-- 10595). The actual sell decision (Leatrix_Plus.lua:3711-3774, function
-- SellJunkFunc) is: quality == Poor AND sellPrice ~= 0, MINUS the
-- exclude list (an item on the list is force-KEPT if Poor, force-SOLD if
-- Common/white), MINUS Keeper Ta'hult pet-quest items (if that setting is
-- on), MINUS unbound grey weapon/armor (if that setting is on, to allow
-- AH-selling instead).

-- Permanent exclusions Leatrix_Plus itself hardcodes and never exposes via
-- LeaPlusDB (Leatrix_Plus.lua:3528-3541) -- items the game reports as
-- sellable but genuinely aren't. Copied because there's nowhere to read
-- them from at runtime.
local ALWAYS_KEEP = {
	[200590] = true, [200593] = true, [200594] = true, [200595] = true,
	[200596] = true, [200592] = true, [200606] = true, [228431] = true,
}

-- Keeper Ta'hult pet-quest items (Leatrix_Plus.lua:3511-3525), excluded
-- only when LeaPlusDB.AutoSellNoKeeperTahult is "On".
local KEEPER_TAHULT_ITEMS = {
	[36812] = true, [62072] = true, [67410] = true, [11406] = true,
	[11944] = true, [25402] = true, [3300] = true, [3670] = true, [6150] = true,
}

local function ParseExcludeList(str)
	local set = {}
	if str and str ~= "" then
		for id in str:gmatch("%d+") do
			set[tonumber(id)] = true
		end
	end
	return set
end

-- sellPrice is a static per-itemID property (unlike upgrade track, which
-- is per-instance -- see Categories.lua), so an itemID-keyed cache is
-- correct here, not just convenient.
local sellPriceCache = {}
local function GetSellPrice(itemID)
	local cached = sellPriceCache[itemID]
	if cached ~= nil then
		return cached or nil
	end
	local sellPrice = select(11, C_Item.GetItemInfo(itemID))
	sellPriceCache[itemID] = sellPrice or false
	return sellPrice
end

-- @return isJunk, sellPrice (sellPrice is returned even when not junk, so
-- callers don't need a second lookup for anything that does need it)
function ns.IsJunk(itemID, quality, isBound, isEquipment)
	local sellPrice = GetSellPrice(itemID)
	if not sellPrice or sellPrice == 0 then
		return false, sellPrice
	end

	if ALWAYS_KEEP[itemID] then
		return false, sellPrice
	end

	local db = _G.LeaPlusDB
	if not db then
		-- No Leatrix_Plus: Blizzard's own bare definition.
		return quality == Enum.ItemQuality.Poor, sellPrice
	end

	if db["AutoSellJunk"] == "Off" then
		-- Leatrix's own auto-sell is explicitly off -- respect that rather
		-- than silently junk-aggregating things the user chose to keep.
		return false, sellPrice
	end

	local exclude = ParseExcludeList(db["AutoSellExcludeList"])

	if quality == Enum.ItemQuality.Poor then
		if exclude[itemID] then
			return false, sellPrice
		end
		if db["AutoSellNoKeeperTahult"] == "On" and KEEPER_TAHULT_ITEMS[itemID] then
			return false, sellPrice
		end
		if isEquipment and db["AutoSellNoGreyGear"] == "On" and not isBound then
			return false, sellPrice
		end
		return true, sellPrice
	end

	-- A Common-quality item explicitly whitelisted is force-sold too --
	-- matches Leatrix_Plus's own whitelist semantics exactly.
	return exclude[itemID] == true, sellPrice
end
