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

-- The Junk/Quest slots' stacked-icon display (UI.lua) only ever shows this
-- many icons -- collection stops here too, not just display, so a bag full
-- of junk (or a quest chain full of turn-in items) doesn't build an array
-- nobody's going to look past. Both are almost always uniform enough
-- (Junk: Poor quality; Quest: whatever the active chain handed out) that
-- "first 4 encountered" loses little real information versus sorting a
-- potentially-large list first.
local ICON_STACK_CAP = 4

-- "Never merge" only actually makes sense for Weapon/Armor (classID 2/4)
-- -- the reason two instances of the same itemID need to stay separate is
-- that each instance can carry different upgrade rank/enchants/sockets
-- (see Categories.lua's reward-track handling), which is a property of
-- weapons and armor specifically, not of "has an equip slot" broadly.
-- Bug fixed 2026-08-16, found by the user in-game: a bare itemEquipLoc
-- check also matches non-equipment inventory types like INVTYPE_BAG (bag-
-- shaped Crafting Order reward items, "artisan bags") and INVTYPE_TABARD/
-- INVTYPE_BODY -- none of which have per-instance state worth preserving,
-- so they were wrongly kept unmerged even though Categories.lua already
-- correctly filed them under Misc, not Equipment. classID matches what
-- Categories.lua checks for its own Equipment-section assignment, so the
-- two are consistent now, not independently guessing at the same thing.
local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4

-- Cheap, synchronous equipment check -- called for every scanned slot
-- (including ones that just add to an existing merged stack), so it stays
-- to the one GetItemInfoInstant call it needs and nothing heavier.
local function IsEquipment(itemID)
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
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

-- Scans the given list of bag IDs into display entries, merging same-
-- itemID, non-equipment slots into one entry regardless of whether they're
-- stackable in the real inventory. Each entry is classified into a
-- section/subcategory via Categories.lua -- Data.lua gathers facts,
-- Categories.lua decides what they mean. Junk (per Junk.lua's rule) never
-- becomes a displayed entry at all -- it's pulled into an aggregate
-- count/value instead, same shape as the empty-slot count, per
-- DESIGN.md invariant 3.
--
-- Parameterized on bagIDs (rather than hardcoded to ns.BAG_IDS) so the same
-- scan/classify machinery serves both the bag view and the bank view
-- (Bank.lua) -- one scanner, two bag-ID lists, not two scanners.
--
-- Returns:
--   entries     : array of { key, itemID, itemLink, icon, quality, count,
--                             isEquipment, isBound, locations, section,
--                             subcategory, itemLevel?, isUpgrade?,
--                             isQuestItem?, questID?, isActiveQuestItem? }
--                 key is a stable identity for the render layer to key
--                 pooled widgets on -- see EntryKey above.
--                 locations = { { bag, slot, count }, ... } -- real slots
--                 backing this entry, in scan order.
--                 itemLevel/isUpgrade are equipment-only (see Pawn.lua);
--                 isUpgrade can be true, false, or nil (Pawn hasn't
--                 resolved it yet -- see pawnPending below).
--                 isQuestItem/questID/isActiveQuestItem come straight from
--                 C_Container.GetContainerItemQuestInfo -- only ever set
--                 on an entry that still made it here, i.e. an *active*
--                 quest item (see questCount below for the inactive ones).
--                 Matches the exact argument shape UI.lua hands to
--                 Blizzard's own ContainerFrameItemButtonMixin:UpdateQuestItem.
--   emptyCount  : empty slots across all combined bags
--   junkCount   : slots occupied by junk (not merged into entries)
--   junkValue   : total vendor sell price of that junk, in copper
--   junkItems   : up to ICON_STACK_CAP { icon, quality } pairs, first-
--                 encountered in scan order -- already exactly what
--                 UI.lua's stacked-icon display needs, no further sorting
--                 or capping required on the render side
--   questCount  : slots occupied by an *inactive* quest item (isQuestItem
--                 true, isActive false -- nothing to Use yet, so it's
--                 collapsed into a badge the same way Junk is, per the
--                 user's own framing: "flag, and hide quest items, and
--                 just display them as a badge unless they have a 'use'
--                 feature"). An active quest item is NOT counted here --
--                 it stays a normal, fully visible entry instead (see
--                 entries above), since isActive is Blizzard's own signal
--                 that the item currently has a real Use action.
--   questItems  : up to ICON_STACK_CAP { icon, quality } pairs for the
--                 inactive quest items counted above
--   pawnPending : true if any equipment item's isUpgrade came back nil --
--                 Model.Update uses this to schedule one short re-scan
local function Scan(bagIDs)
	local entries, byItemID, emptyCount, junkCount, junkValue, junkItems = {}, {}, 0, 0, 0, {}
	local questCount, questItems = 0, {}
	local pawnPending = false

	for _, bagID in ipairs(bagIDs) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bagID, slot)
			if not info then
				emptyCount = emptyCount + 1
			else
				local itemID = info.itemID
				local stackCount = info.stackCount or 1
				local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slot)

				if questInfo.isQuestItem and not questInfo.isActive then
					questCount = questCount + 1
					if #questItems < ICON_STACK_CAP then
						table.insert(questItems, { icon = info.iconFileID, quality = info.quality })
					end
				else
					local isEquipment = IsEquipment(itemID)
					local isJunk, sellPrice = ns.IsJunk(itemID, info.quality, info.isBound, isEquipment)

					if isJunk then
						junkCount = junkCount + 1
						junkValue = junkValue + (sellPrice or 0) * stackCount
						if #junkItems < ICON_STACK_CAP then
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
								isQuestItem = questInfo.isQuestItem,
								questID = questInfo.questID,
								isActiveQuestItem = questInfo.isActive,
							}
							entry.section, entry.subcategory = ns.Categorize(entry, GetItemFacts(itemID, isEquipment))
							if isEquipment then
								-- actualItemLevel accounts for upgrades/gems,
								-- unlike GetItemInfo's static base ilvl.
								entry.itemLevel = C_Item.GetDetailedItemLevelInfo(info.hyperlink)
								entry.isUpgrade = ns.IsUpgrade(info.hyperlink)
								if entry.isUpgrade == nil then
									-- Pawn hasn't resolved this one yet (its
									-- own per-frame throttle) -- re-scan
									-- shortly once it has, rather than
									-- leaving the arrow permanently unset.
									pawnPending = true
								end
							end
							table.insert(entries, entry)
							if not isEquipment then
								byItemID[itemID] = entry
							end
						end
					end
				end
			end
		end
	end

	return entries, emptyCount, junkCount, junkValue, junkItems, questCount, questItems, pawnPending
end

---------------------------------------------------------------
-- Model: the actual bag/bank state, independent of rendering.
---------------------------------------------------------------
-- A model holds entries/emptyCount/junk* for one combined bag-ID list --
-- read-only from the UI's perspective. model.Update() is the only thing
-- that mutates them, and it's the only place a real scan happens;
-- model.OnChanged(fn) subscribes fn to run after every update. Nothing
-- here touches a frame or a widget -- the render layer (UI.lua) is just
-- one listener among however many this ever has.
--
-- getBagIDs is a function, not a static list: the bag view's list
-- (ns.BAG_IDS) never changes at runtime, but the bank models' (Bank.lua's
-- ns.GetPersonalBankBagIDs/ns.GetWarbandBankBagIDs) depend on which bank
-- tabs are currently purchased, which can change mid-session -- re-deriving
-- it on every Update() rather than caching keeps that single-sourced
-- instead of needing its own change-tracking.
-- How long an item stays in the Recent row after it's noticed, and the
-- most items that row ever shows at once (sorted newest-first, per
-- NewRecentTracker below -- oldest of an overflowing bunch just doesn't
-- render, same capped-display idea as ICON_STACK_CAP for Junk/Quest).
local RECENT_WINDOW_SECONDS = 300
local RECENT_ICON_CAP = 6

-- "Recent" isn't a real tracked WoW concept the way isQuestItem/isJunk
-- are -- Blizzard's own C_NewItems.IsNewItem can't be reused for it here:
-- UI.lua's ClearNewItemGlow already calls RemoveNewItem on every single
-- render (to suppress the glow defaulting to shown-on-everything after a
-- reload, since we never run the default bag UI's own hover-driven clear
-- path) which would immediately erase that flag as a signal the moment
-- this model tried to read it. So this keeps its own notion of "recent"
-- instead: an item is recent if it's new to this model's own scan history
-- (a key that wasn't present last Update) or its count went up (looted
-- more of something already held), timestamped with GetTime() and pruned
-- once RECENT_WINDOW_SECONDS old. Session-only by design, not persisted
-- to SavedVariables -- "recent" stops meaning anything across a reload
-- anyway.
local function NewRecentTracker()
	local seenAt = {} -- key -> GetTime() it was last (re-)noticed
	local previousCounts = {} -- key -> count, from the prior scan
	-- Without this, the very first scan (addon load / first bag open, when
	-- previousCounts is still empty) would see every single entry as
	-- "new" -- there's no prior baseline yet to diff against, not because
	-- anything actually just arrived -- and flag the whole bag as Recent
	-- at once. One scan just establishes the baseline instead.
	local hasScannedBefore = false

	-- @return recentEntries: up to RECENT_ICON_CAP entries, newest-noticed
	--   first -- already exactly what UI.lua's Recent row needs to render.
	return function(entries)
		local now = GetTime()
		local currentCounts = {}

		for _, entry in ipairs(entries) do
			currentCounts[entry.key] = entry.count
			if hasScannedBefore then
				local previous = previousCounts[entry.key]
				if not previous or entry.count > previous then
					seenAt[entry.key] = now
				end
			end
		end
		previousCounts = currentCounts
		hasScannedBefore = true

		for key, noticedAt in pairs(seenAt) do
			if now - noticedAt > RECENT_WINDOW_SECONDS then
				seenAt[key] = nil
			end
		end

		local recent = {}
		for _, entry in ipairs(entries) do
			if seenAt[entry.key] then
				table.insert(recent, entry)
			end
		end
		table.sort(recent, function(a, b) return seenAt[a.key] > seenAt[b.key] end)
		while #recent > RECENT_ICON_CAP do
			table.remove(recent)
		end

		return recent, next(seenAt) ~= nil
	end
end

function ns.NewModel(getBagIDs)
	local model = {
		entries = {},
		emptyCount = 0,
		junkCount = 0,
		junkValue = 0,
		junkItems = {},
		questCount = 0,
		questItems = {},
		recentEntries = {},
	}

	local listeners = {}
	local CollectRecent = NewRecentTracker()
	local recentExpiryPending = false

	function model.OnChanged(fn)
		table.insert(listeners, fn)
	end

	function model.Update()
		local pawnPending, hasRecent
		model.entries, model.emptyCount, model.junkCount, model.junkValue, model.junkItems,
			model.questCount, model.questItems, pawnPending = Scan(getBagIDs())
		model.recentEntries, hasRecent = CollectRecent(model.entries)
		if hasRecent and not recentExpiryPending then
			-- Nothing else guarantees another Update() runs once
			-- RECENT_WINDOW_SECONDS passes with no further bag activity --
			-- without this, an item that became recent and then nothing
			-- else happened would just stay in the Recent row forever.
			recentExpiryPending = true
			C_Timer.After(RECENT_WINDOW_SECONDS + 1, function()
				recentExpiryPending = false
				model.Update()
			end)
		end
		if pawnPending then
			-- Pawn couldn't answer for at least one item this pass (its own
			-- per-frame throttle, see Pawn.lua) -- one short deferred re-scan
			-- picks up the settled answer instead of leaving upgrade arrows
			-- unresolved until the next unrelated bag change.
			C_Timer.After(0.2, model.Update)
		end
		for _, fn in ipairs(listeners) do
			fn()
		end
	end

	return model
end

ns.Model = ns.NewModel(function() return ns.BAG_IDS end)
