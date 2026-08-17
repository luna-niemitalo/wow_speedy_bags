local _, ns = ...

-- Classifies an entry into { section, subcategory } for the render layer.
-- Data.lua gathers facts (classID/subClassID/equipLoc/expansionID/isBound);
-- this file is the only place that decides what they mean. Keeping that
-- split means "what counts as Crafting" changes in exactly one place.
--
-- Section order (top to bottom) matches the user's own working Baganator
-- layout, described directly rather than reverse-engineered from a custom
-- config: Crafting, Equipment, (Recent/Empty row), Misc, Old Stuff. The
-- Recent/Empty row sits in the middle deliberately, for ConsolePort nav
-- reasons on the user's existing setup -- worth revisiting once our own
-- nav-graph module (TASKS.md task 1) is real; UI.lua renders it, not this
-- file.
ns.SECTION_ORDER = { "Crafting", "Equipment", "Misc", "OldStuff" }
ns.SECTION_LABELS = {
	Crafting = "Crafting",
	Equipment = "Equipment",
	Misc = "Misc",
	OldStuff = "Old Stuff",
}

local ITEM_CLASS = {
	CONSUMABLE = 0,
	CONTAINER = 1,
	WEAPON = 2,
	GEM = 3,
	ARMOR = 4,
	RECIPE = 9,
	QUEST = 12,
	KEY = 13,
	TRADE_GOODS = 7,
}

-- Item-taxonomy vocabulary (classID/subClassID -> source-based label).
-- This is Blizzard's own item enum, not Baganator's invention -- cross-
-- checked against references/warcraft-wiki's ItemType page and
-- references/vscode-wow-api's Enum data, using Baganator's
-- CategoryViews/CategoryGrouping.lua subclass comments only as a readable
-- index into that enum, not copied logic (its own grouping engine is
-- gated behind Syndicator, which this project deliberately doesn't use --
-- see DESIGN.md).
--
-- "Plants & Rocks" and "Materials" are deliberately coarser than the raw
-- subclasses (Herb+Ore, Cloth+Leather) per the user's own stated reason:
-- those source materials feed multiple professions, so splitting them by
-- profession doesn't mean anything the way a Jewelcrafting-only reagent
-- splitting out does.
local TRADE_GOODS_LABELS = {
	[9] = "Plants & Rocks", -- Herb
	[7] = "Plants & Rocks", -- Metal & Stone
	[5] = "Materials", -- Cloth
	[6] = "Materials", -- Leather
	[4] = "Jewelcrafting",
	[8] = "Cooking",
	[10] = "Elemental",
	[12] = "Enchanting",
	[16] = "Inscription",
	[19] = "Finishing Reagents",
	[18] = "Optional Reagents",
	[1] = "Parts",
}

-- Recipe (classID 9) subclasses map to the same profession labels so a
-- pattern/recipe lands in the same visual column as that profession's
-- materials.
local RECIPE_LABELS = {
	[3] = "Engineering",
	[4] = "Blacksmithing",
	[1] = "Leatherworking",
	[2] = "Tailoring",
	[8] = "Enchanting",
	[10] = "Jewelcrafting",
	[6] = "Alchemy",
	[11] = "Inscription",
	[5] = "Cooking",
	[9] = "Fishing",
	[7] = "First Aid",
}

-- Readable labels for BOE equipment, sorted by slot rather than quality --
-- per the user's own rule: bind-on-equip gear is a trade/sell candidate,
-- so "what slot is this" matters more than "how good is it."
local EQUIP_LOC_LABELS = {
	INVTYPE_HEAD = "Head",
	INVTYPE_NECK = "Neck",
	INVTYPE_SHOULDER = "Shoulder",
	INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest",
	INVTYPE_ROBE = "Chest",
	INVTYPE_BODY = "Shirt",
	INVTYPE_TABARD = "Tabard",
	INVTYPE_WRIST = "Wrist",
	INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist",
	INVTYPE_LEGS = "Legs",
	INVTYPE_FEET = "Feet",
	INVTYPE_FINGER = "Ring",
	INVTYPE_TRINKET = "Trinket",
	INVTYPE_WEAPON = "Weapon",
	INVTYPE_2HWEAPON = "Weapon",
	INVTYPE_WEAPONMAINHAND = "Weapon",
	INVTYPE_WEAPONOFFHAND = "Off Hand",
	INVTYPE_SHIELD = "Off Hand",
	INVTYPE_HOLDABLE = "Off Hand",
	INVTYPE_RANGED = "Ranged",
	INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_RELIC = "Relic",
}

-- Reward-track name (Explorer/Adventurer/Veteran/Champion/Hero/Myth) for
-- soulbound/warbound gear -- corrected 2026-08-16: these are real,
-- persistent item properties (confirmed by the user directly, not a
-- season-throwaway label as first assumed), encoded on the item itself.
--
-- No documented API returns the track name directly -- verified by
-- checking a real, actively-maintained item-level addon
-- (kemayo/wow-simpleitemlevel) that doesn't do this either. The real
-- mechanism: C_TooltipInfo.GetBagItem(bag, slot) returns structured
-- tooltip lines, one of which is locale-independently tagged
-- Enum.TooltipDataLineType.ItemUpgradeLevel (verified against
-- references/vscode-wow-api's Enum.lua) -- that's the "Champion 4/8"-style
-- line. TooltipUtil.SurfaceArgs is NOT needed here: it was removed
-- entirely in patch 11.0.2 (confirmed via web search, cross-referencing a
-- real addon bug report about exactly this) and our client is 12.1.0, so
-- leftText is already the final resolved string.
--
-- Extracting just the track name from that line's text is still string
-- parsing (locale-dependent for the word itself, fine for a single-locale
-- personal addon) -- untested against a real live tooltip since this
-- can't be exercised outside the game client; falls back to item quality
-- if the pattern doesn't match (no track line at all, e.g. non-track
-- gear) rather than showing nothing.
--
-- Cached per-instance (keyed by entry.key, the same per-item GUID identity
-- used for widget pooling -- see Data.lua's EntryKey), not per-itemID:
-- upgrade rank/track is state on the physical item, not the itemID, so two
-- copies of the same gear can legitimately sit on different tracks. An
-- itemID-keyed cache would silently misreport the second copy.
--
-- No invalidation needed, confirmed by the user (who actually plays this
-- system, unlike this comment's author): an item's track name is fixed
-- for that item's whole lifetime -- upgrading via the Upgrade UI only
-- moves rank within the same track (Champion 4/8 -> 5/8), never crosses
-- into a different track (Champion -> Hero requires a new item drop,
-- which is a different GUID and a fresh cache entry anyway). So this
-- cache is permanently valid per key, not just "cheap enough to not
-- matter" -- there's nothing for it to go stale against.
local trackNameCache = {}

local function GetUpgradeTrackName(key, bagID, slot)
	local cached = trackNameCache[key]
	if cached ~= nil then
		return cached or nil
	end

	local name
	local data = C_TooltipInfo.GetBagItem(bagID, slot)
	if data then
		for _, line in ipairs(data.lines) do
			if line.type == Enum.TooltipDataLineType.ItemUpgradeLevel then
				name = line.leftText:match("^(%a[%a%s]-)%s*%d")
				break
			end
		end
	end

	trackNameCache[key] = name or false
	return name
end

-- Quality-tier labels -- the fallback when GetUpgradeTrackName finds no
-- track line (non-track gear) or the format doesn't match what was
-- assumed above.
local QUALITY_LABELS = {
	[Enum.ItemQuality.Poor] = "Poor",
	[Enum.ItemQuality.Common] = "Common",
	[Enum.ItemQuality.Uncommon] = "Uncommon",
	[Enum.ItemQuality.Rare] = "Rare",
	[Enum.ItemQuality.Epic] = "Epic",
	[Enum.ItemQuality.Legendary] = "Legendary",
	[Enum.ItemQuality.Artifact] = "Artifact",
	[Enum.ItemQuality.Heirloom] = "Heirloom",
}

-- expansionID -> display name. Anything below LE_EXPANSION_LEVEL_CURRENT
-- is "old"; the label is cosmetic. A future expansion not yet in this
-- table falls back to "Previous Expansion" rather than erroring.
local EXPANSION_LABELS = {
	[LE_EXPANSION_CLASSIC] = "Classic",
	[LE_EXPANSION_BURNING_CRUSADE] = "The Burning Crusade",
	[LE_EXPANSION_WRATH_OF_THE_LICH_KING] = "Wrath of the Lich King",
	[LE_EXPANSION_CATACLYSM] = "Cataclysm",
	[LE_EXPANSION_MISTS_OF_PANDARIA] = "Mists of Pandaria",
	[LE_EXPANSION_WARLORDS_OF_DRAENOR] = "Warlords of Draenor",
	[LE_EXPANSION_LEGION] = "Legion",
	[LE_EXPANSION_BATTLE_FOR_AZEROTH] = "Battle for Azeroth",
	[LE_EXPANSION_SHADOWLANDS] = "Shadowlands",
	[LE_EXPANSION_DRAGONFLIGHT] = "Dragonflight",
	[LE_EXPANSION_WAR_WITHIN] = "The War Within",
	[LE_EXPANSION_MIDNIGHT] = "Midnight",
}

-- @param entry { quality, isBound, ... } -- see Data.lua
-- @param facts { classID, subClassID, equipLoc, expansionID, isEquipment }
-- @return section, subcategory
function ns.Categorize(entry, facts)
	-- Old expansion content is pulled out of its normal section regardless
	-- of type -- old gear, old recipes, and old quest items are all just
	-- clutter by this point. Unknown expansionID (uncached item) never
	-- counts as old -- see Data.lua's GetItemFacts note.
	if facts.expansionID and facts.expansionID < LE_EXPANSION_LEVEL_CURRENT then
		return "OldStuff", EXPANSION_LABELS[facts.expansionID] or "Previous Expansion"
	end

	if facts.classID == ITEM_CLASS.TRADE_GOODS then
		return "Crafting", TRADE_GOODS_LABELS[facts.subClassID] or "Other"
	end
	if facts.classID == ITEM_CLASS.RECIPE then
		return "Crafting", RECIPE_LABELS[facts.subClassID] or "Recipes"
	end
	if facts.classID == ITEM_CLASS.GEM then
		return "Crafting", "Jewelcrafting"
	end

	if facts.classID == ITEM_CLASS.WEAPON or facts.classID == ITEM_CLASS.ARMOR then
		if entry.isBound then
			local loc = entry.locations[1]
			local track = GetUpgradeTrackName(entry.key, loc.bag, loc.slot)
			return "Equipment", track or QUALITY_LABELS[entry.quality] or "Equipment"
		end
		return "Equipment", EQUIP_LOC_LABELS[facts.equipLoc] or "Equipment"
	end

	if facts.classID == ITEM_CLASS.CONSUMABLE then
		return "Misc", "Consumable"
	end
	if facts.classID == ITEM_CLASS.CONTAINER then
		return "Misc", "Bags"
	end
	if facts.classID == ITEM_CLASS.QUEST then
		return "Misc", "Quest"
	end
	if facts.classID == ITEM_CLASS.KEY then
		return "Misc", "Key"
	end

	return "Misc", "Miscellaneous"
end
