local _, ns = ...

-- Combined-view bags for this MVP. Bank/keyring/reagent-bank are explicitly
-- out of scope -- see ../TODO.md.
ns.BAG_IDS = {
	Enum.BagIndex.Backpack,
	Enum.BagIndex.Bag_1,
	Enum.BagIndex.Bag_2,
	Enum.BagIndex.Bag_3,
	Enum.BagIndex.Bag_4,
	Enum.BagIndex.ReagentBag,
}

-- The Junk slot's stacked-icon display (UI.lua) only ever shows this many
-- icons -- collection stops here too, not just display, so a bag full of
-- junk doesn't build an array nobody's going to look past. Junk is almost
-- always uniformly Poor quality anyway (unlike Plumber's loot-window
-- groups, which can span a wider range), so "first 4 encountered" loses
-- little real information versus sorting a potentially-large list by
-- quality first.
local JUNK_ICON_CAP = 4

-- Cheap, synchronous equipment check -- called for every scanned slot
-- (including ones that just add to an existing merged stack), so it stays
-- to the one GetItemInfoInstant call it needs and nothing heavier.
local function IsEquipment(itemID)
	local _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(itemID)
	return itemEquipLoc ~= nil and itemEquipLoc ~= ""
end

-- Classification facts for an item, gathered once per new entry (never for
-- a slot that just adds to an existing merged stack) and handed to
-- Categories.lua -- Data.lua only gathers raw facts, it never decides what
-- section/subcategory anything belongs in (see Categories.lua).
--
-- classID/subClassID/itemEquipLoc come from GetItemInfoInstant, which is
-- synchronous even for an item the client hasn't cached yet (unlike
-- GetItemInfo). expansionID is only available from GetItemInfo, which CAN
-- return nil on an uncached item -- callers must treat a nil expansionID
-- as "unknown," not "current expansion." GetItemInfo is the heavier of the
-- two calls, which is exactly why this only runs once per new entry,
-- not once per scanned slot.
local function GetItemFacts(itemID, isEquipment)
	local _, _, _, itemEquipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	local expansionID = select(15, C_Item.GetItemInfo(itemID))
	return {
		classID = classID,
		subClassID = subClassID,
		equipLoc = itemEquipLoc,
		expansionID = expansionID,
		isEquipment = isEquipment,
	}
end

-- A stable identity for an entry, independent of where it lands in scan
-- order -- scan order shifts whenever a slot earlier in bag/slot order
-- gains or loses an item (e.g. crafting turns part of a reagent stack
-- into a new item type), which would otherwise silently reassign an
-- existing render-layer widget to a different item mid-session. Merged
-- (non-equipment) stacks are identified by itemID -- that's exactly what
-- "merged" means here. Equipment needs a real per-instance identity since
-- two identical rings are two different actionable items; C_Item.GetItemGUID
-- is stable across slot moves, unlike bag/slot itself.
local function EntryKey(itemID, isEquipment, bagID, slot)
	if isEquipment then
		local guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
		return "guid:" .. tostring(guid)
	end
	return "item:" .. tostring(itemID)
end

-- Scans every combined bag into display entries, merging same-itemID,
-- non-equipment slots into one entry regardless of whether they're
-- stackable in the real inventory. Each entry is classified into a
-- section/subcategory via Categories.lua -- Data.lua gathers facts,
-- Categories.lua decides what they mean. Junk (per Junk.lua's rule) never
-- becomes a displayed entry at all -- it's pulled into an aggregate
-- count/value instead, same shape as the empty-slot count, per
-- DESIGN.md invariant 3.
--
-- Returns:
--   entries    : array of { key, itemID, itemLink, icon, quality, count,
--                            isEquipment, isBound, locations, section,
--                            subcategory }
--                key is a stable identity for the render layer to key
--                pooled widgets on -- see EntryKey above.
--                locations = { { bag, slot, count }, ... } -- real slots
--                backing this entry, in scan order
--   emptyCount : empty slots across all combined bags
--   junkCount  : slots occupied by junk (not merged into entries)
--   junkValue  : total vendor sell price of that junk, in copper
--   junkItems  : up to JUNK_ICON_CAP { icon, quality } pairs, first-
--                encountered in scan order -- already exactly what
--                UI.lua's stacked-icon display needs, no further sorting
--                or capping required on the render side
local function Scan()
	local entries, byItemID, emptyCount, junkCount, junkValue, junkItems = {}, {}, 0, 0, 0, {}

	for _, bagID in ipairs(ns.BAG_IDS) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bagID, slot)
			if not info then
				emptyCount = emptyCount + 1
			else
				local itemID = info.itemID
				local stackCount = info.stackCount or 1
				local isEquipment = IsEquipment(itemID)
				local isJunk, sellPrice = ns.IsJunk(itemID, info.quality, info.isBound, isEquipment)

				if isJunk then
					junkCount = junkCount + 1
					junkValue = junkValue + (sellPrice or 0) * stackCount
					if #junkItems < JUNK_ICON_CAP then
						table.insert(junkItems, { icon = info.iconFileID, quality = info.quality })
					end
				else
					local entry = (not isEquipment) and byItemID[itemID]

					if entry then
						entry.count = entry.count + stackCount
						table.insert(entry.locations, { bag = bagID, slot = slot, count = stackCount })
					else
						entry = {
							key = EntryKey(itemID, isEquipment, bagID, slot),
							itemID = itemID,
							itemLink = info.hyperlink,
							icon = info.iconFileID,
							quality = info.quality,
							count = stackCount,
							isEquipment = isEquipment,
							isBound = info.isBound,
							locations = { { bag = bagID, slot = slot, count = stackCount } },
						}
						entry.section, entry.subcategory = ns.Categorize(entry, GetItemFacts(itemID, isEquipment))
						table.insert(entries, entry)
						if not isEquipment then
							byItemID[itemID] = entry
						end
					end
				end
			end
		end
	end

	return entries, emptyCount, junkCount, junkValue, junkItems
end

---------------------------------------------------------------
-- Model: the actual bag state, independent of rendering.
---------------------------------------------------------------
-- ns.Model.entries/emptyCount are the current, already-scanned state --
-- read-only from the UI's perspective. ns.Model.Update() is the only
-- thing that mutates them, and it's the only place a real bag scan
-- happens; ns.Model.OnChanged(fn) subscribes fn to run after every
-- update. Nothing here touches a frame or a widget -- the render layer
-- (UI.lua) is just one listener among however many this ever has.
ns.Model = {
	entries = {},
	emptyCount = 0,
	junkCount = 0,
	junkValue = 0,
	junkItems = {},
}

local listeners = {}

function ns.Model.OnChanged(fn)
	table.insert(listeners, fn)
end

function ns.Model.Update()
	ns.Model.entries, ns.Model.emptyCount, ns.Model.junkCount, ns.Model.junkValue, ns.Model.junkItems = Scan()
	for _, fn in ipairs(listeners) do
		fn()
	end
end
