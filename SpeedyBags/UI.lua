local _, ns = ...

local SLOT_SIZE = 30
local SLOT_PAD = 4
local MARGIN = 12
local TITLE_HEIGHT = 24
local SECTION_HEADER_HEIGHT = 20
local SUBCAT_LABEL_HEIGHT = 16
local SUBCAT_COLS = 4 -- items per row within one subcategory block
local SUBCAT_PAD_X = 16 -- gap between subcategory blocks on the same row
local SUBCAT_PAD_Y = 14 -- gap between rows of subcategory blocks
local SECTION_PAD_Y = 18 -- gap after a section before the next header
local FRAME_WIDTH = MARGIN * 2 + 5 * (SUBCAT_COLS * SLOT_SIZE + (SUBCAT_COLS - 1) * SLOT_PAD) + 4 * SUBCAT_PAD_X

-- Fixed-width subcategory blocks, not dynamically measured against label
-- text width -- simpler than GetStringWidth-based wrapping, and "no need
-- to make it super editable" per the user's own framing. A long label can
-- overflow its block visually; not a correctness problem, just cosmetic.
local SUBCAT_WIDTH = SUBCAT_COLS * SLOT_SIZE + (SUBCAT_COLS - 1) * SLOT_PAD

local frame = CreateFrame("Frame", "SpeedyBagsFrame", UIParent, "BackdropTemplate")
frame:SetPoint("CENTER")
frame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
ns.Frame = frame

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -14)
title:SetText("SpeedyBags")

---------------------------------------------------------------
-- Widget pools
---------------------------------------------------------------
-- Slot widgets are pooled by entry.key (stable item identity, see
-- Data.lua's EntryKey), never by list position and never destroyed. This
-- matters, not just tidiness: scan order shifts whenever a slot earlier
-- in bag/slot order gains or loses an item (crafting, splitting a stack,
-- looting), which would otherwise silently reassign an existing widget to
-- a different item mid-session -- the exact failure mode this pooling
-- avoids. Not a full cursor-stability guarantee (see TASKS.md task 2,
-- which is about ConsolePort's own reselection), but a prerequisite for
-- it: the render layer must stop scrambling identity on its own first.
local slotPool = {}
local labelPool = {} -- section headers + subcategory labels, keyed by a string tag
local aggregateWidgets = {} -- "empty" / "junk" -> widget
local nextSlotID = 0

-- Inherits Blizzard's real ContainerFrameItemButtonTemplate rather than a
-- plain button. UseContainerItem/PickupContainerItem* are protected --
-- Blizzard's own click handler (ContainerFrameItemButtonMixin:OnClick) can
-- call them because that code is Blizzard's own (untainted); the identical
-- call from OUR OnClick never can, combat or not -- confirmed in-game, see
-- ../DESIGN.md "Protected functions (taint)". Every reference addon
-- (AdiBags, Baganator, BetterBags) inherits this exact template for
-- exactly this reason. Its OnLoad/OnClick path touches nothing on the
-- parent frame as long as we drive SetBagID/SetID ourselves instead of
-- calling its optional :Initialize() (which does) -- verified against
-- ContainerFrame.lua directly, not assumed.
-- *PickupContainerItem is not actually protected, only UseContainerItem is
-- -- but both go through Blizzard's click handler now for one consistent
-- path instead of half our own OnClick, half Blizzard's.
local function AcquireSlot(key)
	local btn = slotPool[key]
	if btn then return btn end

	nextSlotID = nextSlotID + 1
	btn = CreateFrame("ItemButton", "SpeedyBagsSlot"..nextSlotID, frame, "ContainerFrameItemButtonTemplate")
	btn:SetSize(SLOT_SIZE, SLOT_SIZE)

	-- Blizzard's default button chrome (Interface\Buttons\UI-Quickslot2),
	-- not the quality border -- that's IconBorder (Interface\Common\
	-- WhiteIconFrame, ItemButtonTemplate.xml:41), set automatically by
	-- SetItemButtonQuality and left alone here. Without this, both render
	-- at once and look like a double border.
	btn:SetNormalTexture(nil)

	slotPool[key] = btn
	return btn
end

-- ContainerFrameItemButtonMixin:UpdateNewItem (ContainerFrame.lua:1688) is
-- what would normally show/hide the blue "new item" glow based on
-- C_NewItems.IsNewItem -- we never call it, since "Recent items" isn't a
-- real tracked feature yet (see TODO.md), so leaving the glow alone would
-- mean it never gets cleared at all. Worse, it defaults to shown right
-- after a reload/relog/character-switch, when the client hasn't yet run
-- Blizzard's own bag-frame code that would normally clear it (opening the
-- default bag view, hovering items there -- ContainerFrameItemButtonMixin:
-- OnUpdate does this on hover, ContainerFrame.lua:1541) -- so every item
-- shows the glow at once instead of just genuinely-new ones. Replicating
-- that same clear (RemoveNewItem + hide texture + stop both anims) here
-- is the correct fix until "Recent items" is real: suppress it outright
-- rather than leave it in this broken always-on state.
local function ClearNewItemGlow(btn, bagID, slot)
	C_NewItems.RemoveNewItem(bagID, slot)
	btn.NewItemTexture:Hide()
	btn.BattlepayItemTexture:Hide()
	if btn.flashAnim:IsPlaying() or btn.newitemglowAnim:IsPlaying() then
		btn.flashAnim:Stop()
		btn.newitemglowAnim:Stop()
	end
end

-- Item level text + Pawn upgrade arrow, equipment-only (see Data.lua/
-- Pawn.lua for where entry.itemLevel/isUpgrade come from). UpgradeIcon is
-- a native ContainerFrameItemButtonTemplate region (ContainerFrame.xml:104,
-- atlas "bags-greenarrow") -- Pawn itself just toggles this same region on
-- Blizzard's default bag buttons (PawnBags.lua's UpdateItemButtonUpgradeIcon),
-- so no new texture is needed here either.
local function SetEquipmentOverlay(btn, entry)
	if not entry.isEquipment then
		btn.UpgradeIcon:Hide()
		if btn.ItemLevel then
			btn.ItemLevel:Hide()
		end
		return
	end

	btn.UpgradeIcon:SetShown(entry.isUpgrade == true)

	if not btn.ItemLevel then
		btn.ItemLevel = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		-- The only free corner: Count is BOTTOMRIGHT, UpgradeIcon is
		-- TOPLEFT, IconQuestTexture is top-center (all native
		-- ContainerFrameItemButtonTemplate positions).
		btn.ItemLevel:SetPoint("BOTTOMLEFT", 2, 2)
	end
	btn.ItemLevel:SetText(entry.itemLevel or "")
	btn.ItemLevel:Show()
end

local function AcquireLabel(key, fontTemplate)
	local fs = labelPool[key]
	if fs then return fs end

	fs = frame:CreateFontString(nil, "OVERLAY", fontTemplate)
	labelPool[key] = fs
	return fs
end

-- Empty-slot and Junk widgets share this shape: a plain frame with a dark
-- background, an optional icon, and a count -- neither is a real item, so
-- neither uses ContainerFrameItemButtonTemplate. Empty leaves Icon unset
-- (just background+count, as before); Junk sets it to Blizzard's own
-- "bags-junkcoin" atlas (ContainerFrame.xml:139, the JunkIcon overlay
-- Blizzard's own default bag UI already uses to mark junk items) --
-- checked Plumber's loot-window "Junk Items" grouping for a matching icon
-- first, but it doesn't have one: it composites up to 4 of the actual
-- merged items' own icons dynamically (LootUI_Main.lua's SetMergedItem),
-- no static asset to borrow. Blizzard's own junk badge is the more
-- consistent choice anyway, given the item slots already inherit
-- Blizzard's real container-frame machinery elsewhere in this addon.
local function AcquireAggregateSlot(key, frameName)
	local btn = aggregateWidgets[key]
	if btn then return btn end

	btn = CreateFrame("Frame", frameName, frame)
	btn:SetSize(SLOT_SIZE, SLOT_SIZE)

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)

	-- Centered, not stretched to fill the slot: "bags-junkcoin" is a small
	-- corner-badge atlas in Blizzard's own usage (ContainerFrame.xml's
	-- JunkIcon, useAtlasSize="true") -- forcing it to SLOT_SIZE would
	-- distort it. SetAtlas's own useAtlasSize handles sizing at render
	-- time; this texture just needs a center anchor to size around.
	btn.Icon = btn:CreateTexture(nil, "ARTWORK")
	btn.Icon:SetPoint("CENTER", 0, 4)
	btn.Icon:Hide()

	btn.Count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.Count:SetPoint("BOTTOM", 0, 2)

	aggregateWidgets[key] = btn
	return btn
end

-- Junk's stacked-icon look, matching Plumber's actual LootUI_Main.lua
-- SetMergedItem algorithm (grayscale-darkened real item icons layered
-- diagonally, one per junk item, up to Data.lua's JUNK_ICON_CAP) --
-- Plumber has no static "junk icon" asset to copy, this is the real
-- mechanism it uses for its own merged-junk loot display, replicated
-- here. Empty junk (no items) shows Blizzard's own darkened
-- "bags-junkcoin" badge as a persistent placeholder instead, so the slot
-- is never just blank -- it's always there, per the user's own request.
local STACK_OVERLAP = 0.15
local function SetJunkVisual(btn, junkItems)
	local n = #junkItems

	if n == 0 then
		btn.Icon:SetAtlas("bags-junkcoin", true)
		btn.Icon:SetVertexColor(0.4, 0.4, 0.4)
		btn.Icon:Show()
		if btn.StackIcons then
			for _, tex in ipairs(btn.StackIcons) do
				tex:Hide()
			end
		end
		return
	end

	btn.Icon:Hide()
	btn.StackIcons = btn.StackIcons or {}

	local iconSize = SLOT_SIZE / (1 + (n - 1) * STACK_OVERLAP)
	local offset = iconSize * STACK_OVERLAP

	for i = 1, n do
		local tex = btn.StackIcons[i]
		if not tex then
			tex = btn:CreateTexture(nil, "ARTWORK")
			btn.StackIcons[i] = tex
		end

		local item = junkItems[i]
		tex:SetTexture(item.icon)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", btn, "TOPLEFT", (i - 1) * offset, -(i - 1) * offset)
		tex:SetSize(iconSize, iconSize)
		-- Grayscale-darken each layer going down the stack, same as
		-- Plumber -- the icon keeps its real colors, just dimmer under
		-- whatever's stacked on top of it.
		local a = 1 - (i - 1) * 0.2
		tex:SetVertexColor(a, a, a)
		tex:Show()
	end

	for i = n + 1, #btn.StackIcons do
		btn.StackIcons[i]:Hide()
	end
end

---------------------------------------------------------------
-- Layout
---------------------------------------------------------------
-- Groups Model entries into { [section] = { [subcategory] = {entries} } },
-- per Categories.lua's classification. Pure data reshaping, no widgets.
local function GroupEntries()
	local sections = {}
	for _, entry in ipairs(ns.Model.entries) do
		local bySubcat = sections[entry.section]
		if not bySubcat then
			bySubcat = {}
			sections[entry.section] = bySubcat
		end
		local list = bySubcat[entry.subcategory]
		if not list then
			list = {}
			bySubcat[entry.subcategory] = list
		end
		table.insert(list, entry)
	end
	return sections
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- Renders one subcategory block (label + its items, wrapping within the
-- block if there are more than SUBCAT_COLS) at (x, y). Returns the
-- block's rendered height.
local function RenderSubcategory(x, y, sectionName, label, entries, usedKeys, usedLabels)
	local labelKey = "sub:"..sectionName..":"..label
	local fs = AcquireLabel(labelKey, "GameFontNormalSmall")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
	fs:SetText(label)
	fs:Show()
	usedLabels[labelKey] = true

	local itemY = y - SUBCAT_LABEL_HEIGHT
	for i, entry in ipairs(entries) do
		local col = (i - 1) % SUBCAT_COLS
		local row = math.floor((i - 1) / SUBCAT_COLS)
		local btn = AcquireSlot(entry.key)
		usedKeys[entry.key] = true

		local loc = entry.locations[1]
		btn:SetBagID(loc.bag)
		btn:SetID(loc.slot)
		ClearNewItemGlow(btn, loc.bag, loc.slot)
		btn:SetItemButtonTexture(entry.icon)
		btn:SetItemButtonQuality(entry.quality, entry.itemLink)
		btn:SetItemButtonCount(entry.count > 1 and entry.count or nil)
		SetEquipmentOverlay(btn, entry)

		btn:ClearAllPoints()
		btn:SetPoint(
			"TOPLEFT", frame, "TOPLEFT",
			x + col * (SLOT_SIZE + SLOT_PAD),
			itemY - row * (SLOT_SIZE + SLOT_PAD)
		)
		btn:Show()
	end

	local rows = math.ceil(#entries / SUBCAT_COLS)
	return SUBCAT_LABEL_HEIGHT + rows * SLOT_SIZE + (rows - 1) * SLOT_PAD
end

-- Renders one section (header + its subcategory blocks, wrapping to a new
-- row of blocks at the frame edge) starting at y. Returns the y to
-- continue at, unchanged if the section has nothing in it -- empty
-- sections don't reserve space or show a header.
local function RenderSection(sectionName, bySubcat, y, usedKeys, usedLabels)
	if not bySubcat or not next(bySubcat) then
		return y
	end

	local headerKey = "header:"..sectionName
	local header = AcquireLabel(headerKey, "GameFontNormalLarge")
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN, y)
	header:SetText(ns.SECTION_LABELS[sectionName] or sectionName)
	header:Show()
	usedLabels[headerKey] = true
	y = y - SECTION_HEADER_HEIGHT

	local x = MARGIN
	local rowHeight = 0
	for _, subcatName in ipairs(SortedKeys(bySubcat)) do
		if x > MARGIN and x + SUBCAT_WIDTH > FRAME_WIDTH - MARGIN then
			x = MARGIN
			y = y - rowHeight - SUBCAT_PAD_Y
			rowHeight = 0
		end
		local height = RenderSubcategory(x, y, sectionName, subcatName, bySubcat[subcatName], usedKeys, usedLabels)
		rowHeight = math.max(rowHeight, height)
		x = x + SUBCAT_WIDTH + SUBCAT_PAD_X
	end
	y = y - rowHeight - SECTION_PAD_Y

	return y
end

-- Empty-slot and Junk aggregate widgets share one row, positioned between
-- Equipment and Misc to match the user's existing Baganator layout, which
-- puts its Recent/Empty row there deliberately for ConsolePort nav
-- reasons -- worth revisiting once our own nav-graph module (TASKS.md
-- task 1) is real. "Recent items" (the other half of that row in the
-- reference layout) isn't tracked yet -- see TODO.md. Junk is never
-- rendered as individual slots (DESIGN.md invariant 3) -- Data.lua's Scan
-- already pulled junk out into ns.Model.junkCount/junkValue rather than
-- creating entries for it.
local function RenderAggregateRow(y, usedLabels)
	local x = MARGIN

	if ns.Model.emptyCount > 0 then
		local fs = AcquireLabel("sub:Empty", "GameFontNormalSmall")
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
		fs:SetText("Empty")
		fs:Show()
		usedLabels["sub:Empty"] = true

		local btn = AcquireAggregateSlot("empty", "SpeedyBagsEmptySlot")
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
		btn.Count:SetText(ns.Model.emptyCount)
		btn:Show()

		x = x + SLOT_SIZE + SUBCAT_PAD_X
	elseif aggregateWidgets["empty"] then
		aggregateWidgets["empty"]:Hide()
	end

	-- Always rendered, even with zero junk -- a persistent slot (see
	-- SetJunkVisual) rather than popping in and out of the layout.
	do
		local fs = AcquireLabel("sub:Junk", "GameFontNormalSmall")
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
		fs:SetText("Junk")
		fs:Show()
		usedLabels["sub:Junk"] = true

		local btn = AcquireAggregateSlot("junk", "SpeedyBagsJunkSlot")
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
		SetJunkVisual(btn, ns.Model.junkItems)
		btn.Count:SetText(ns.Model.junkCount > 0 and ns.Model.junkCount or "")
		btn:Show()

		-- The count alone doesn't say whether a vendor trip is worth it.
		btn:EnableMouse(true)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Junk")
			if ns.Model.junkCount > 0 then
				GameTooltip:AddLine(C_CurrencyInfo.GetCoinTextureString(ns.Model.junkValue), 1, 1, 1)
			else
				GameTooltip:AddLine("Nothing to sell.", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
	end

	return y - SUBCAT_LABEL_HEIGHT - SLOT_SIZE - SECTION_PAD_Y
end

-- Renders the current ns.Model state. Never scans bags itself -- that's
-- Model.Update's job; this only reacts to whatever the model already has.
function ns.Refresh()
	if not frame:IsShown() then return end

	local sections = GroupEntries()
	local usedKeys, usedLabels = {}, {}
	local y = -(MARGIN + TITLE_HEIGHT)

	for _, sectionName in ipairs(ns.SECTION_ORDER) do
		y = RenderSection(sectionName, sections[sectionName], y, usedKeys, usedLabels)
		if sectionName == "Equipment" then
			y = RenderAggregateRow(y, usedLabels)
		end
	end

	for key, btn in pairs(slotPool) do
		if not usedKeys[key] then
			btn:Hide()
		end
	end
	for key, fs in pairs(labelPool) do
		if not usedLabels[key] then
			fs:Hide()
		end
	end

	-- y already includes the top margin (the starting offset below); only
	-- the bottom margin needs adding here.
	frame:SetSize(FRAME_WIDTH, MARGIN - y)
end

function ns.Show()
	frame:Show()
	ns.Model.Update()
end

function ns.Hide()
	frame:Hide()
end

function ns.Toggle()
	if frame:IsShown() then
		ns.Hide()
	else
		ns.Show()
	end
end

-- The render layer is just one Model listener; it renders whatever the
-- model already has, whenever the model says something changed.
ns.Model.OnChanged(ns.Refresh)
