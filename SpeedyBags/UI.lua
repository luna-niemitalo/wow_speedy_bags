local _, ns = ...

-- Blizzard's real default item-slot size, matching what Count/UpgradeIcon/
-- IconBorder are actually proportioned for (native atlas sizes, font
-- sizes). Shrunk to 30 earlier for a denser categorized layout; the user
-- found icons too small and covered by their own overlay text as a
-- result -- reverted, since the real problem was fighting Blizzard's
-- proportions rather than a font-size tweak.
local SLOT_SIZE = 37
local SLOT_PAD = 4
local MARGIN = 12
local TITLE_HEIGHT = 24
-- Sized to fit the currency row's icon+border (20px icon + 3px border on
-- each side, see RenderCurrencyRow), not just its font -- bumped from an
-- original flat 20 when both the icon and font were made bigger per user
-- feedback ("icons are tiny AF").
local CURRENCY_ROW_HEIGHT = 26
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

-- Item level text + Pawn upgrade arrow, equipment-only (see Data.lua/
-- Pawn.lua for where entry.itemLevel/isUpgrade come from). UpgradeIcon is
-- a native ContainerFrameItemButtonTemplate region (ContainerFrame.xml:104,
-- atlas "bags-greenarrow") -- Pawn itself just toggles this same region on
-- Blizzard's default bag buttons (PawnBags.lua's UpdateItemButtonUpgradeIcon),
-- so no new texture is needed here either.
--
-- ItemLevel shares Count's own corner (BOTTOMRIGHT) rather than getting
-- its own, per the user's actual corner-assignment convention (their own
-- reference screenshot: item level, keystone level, and quantity all
-- stack in one corner, safe because they never co-occur on the same
-- item -- equipment's own count is never shown here since it's always 1,
-- see UI.lua's SetItemButtonCount call). Colored by item quality, same as
-- the slot's own border -- Count stays plain white -- so the two are
-- visually distinct at a glance even sharing a corner, same as their
-- reference setup.
--
-- Module-level (not per-view): pure functions of (btn, entry)/(btn,
-- bagID, slot), nothing here depends on which view's frame owns btn.
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
		btn.ItemLevel:SetPoint("BOTTOMRIGHT", -2, 2)
	end
	btn.ItemLevel:SetText(entry.itemLevel or "")
	local r, g, b = C_Item.GetItemQualityColor(entry.quality or Enum.ItemQuality.Common)
	btn.ItemLevel:SetTextColor(r, g, b)
	btn.ItemLevel:Show()
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

-- Groups Model entries into { [section] = { [subcategory] = {entries} } },
-- per Categories.lua's classification. Pure data reshaping, no widgets.
local function GroupEntries(model)
	local sections = {}
	for _, entry in ipairs(model.entries) do
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

-- Builds one independent bag view: its own frame, its own pooled widgets,
-- bound to its own model. The bag window and the bank window are the same
-- rendering machinery running twice, per the user's "bank UI as a
-- reflection of this" ask -- one factory, not two copy-pasted files, so a
-- future layout/category fix never needs to be made twice.
--
-- opts: { name, title, model, slotPrefix, point = {point, relPoint, x, y} }
local function NewBagView(opts)
	local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
	frame:SetPoint(unpack(opts.point))
	-- Bug fixed 2026-08-17, found by the user in-game: frame appeared behind
	-- static UI elements. Same strata as Blizzard's own bag frame (MEDIUM,
	-- confirmed in ContainerFrame.xml -- not the actual issue), but Blizzard's
	-- also sets toplevel="true" (ContainerFrame.xml:290's
	-- ContainerFrameCombinedBags), which auto-raises within its strata; ours
	-- didn't have that, so it sat wherever it happened to land in creation
	-- order relative to other MEDIUM-strata frames.
	frame:SetToplevel(true)
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

	-- ConsolePort marker (DESIGN.md invariant 1/5's fallback net --
	-- ConsolePortNode does a geometric scan of every mouse-enabled visible
	-- frame, so the drag-enabled backdrop above would otherwise itself be a
	-- valid up/down/left/right nav candidate alongside the real item slots
	-- it contains). nodeignore removes just this frame from candidate
	-- selection; its children (slots, the Junk slot, currency row) are
	-- unaffected and still reachable.
	frame:SetAttribute("nodeignore", true)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -14)
	title:SetText(opts.title)

	---------------------------------------------------------------
	-- Widget pools (per view -- a bag-view slot and a bank-view slot are
	-- never the same widget, since they're parented to different frames)
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
	local bgPool = {} -- subcategory group backgrounds, keyed the same way as their label
	local aggregateWidgets = {} -- "empty" / "junk" -> widget
	local currencyPool = {} -- "gold" / "cur:<currencyTypesID>" -> widget
	local headerPool = {} -- section name -> collapsible header button
	local nextSlotID = 0

	-- Forward-declared: the header button's click handler (below) needs to
	-- call Refresh to re-flow the layout after a collapse/expand toggle,
	-- but Refresh itself is only defined near the bottom of this factory.
	local Refresh

	-- A subtle background per subcategory block (LUNA_NOTES.md), just enough
	-- lighter than the frame's own backdrop that adjacent groups read as
	-- visually separate without needing a per-group unique color.
	local function AcquireGroupBackground(key)
		local bg = bgPool[key]
		if bg then return bg end

		bg = frame:CreateTexture(nil, "BORDER")
		bg:SetColorTexture(1, 1, 1, 0.05)
		bgPool[key] = bg
		return bg
	end

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
		btn = CreateFrame("ItemButton", opts.slotPrefix..nextSlotID, frame, "ContainerFrameItemButtonTemplate")
		btn:SetSize(SLOT_SIZE, SLOT_SIZE)

		-- Blizzard's default button chrome (Interface\Buttons\UI-Quickslot2),
		-- not the quality border -- that's IconBorder (Interface\Common\
		-- WhiteIconFrame, ItemButtonTemplate.xml:41), set automatically by
		-- SetItemButtonQuality and left alone here. Without this, both render
		-- at once and look like a double border.
		-- Bug fixed 2026-08-17: SetNormalTexture(nil) crashes -- the Button
		-- widget's setter genuinely doesn't accept nil (confirmed live, addon
		-- broke). The real fix, per BetterBags' own documented workaround for
		-- this exact ContainerFrameItemButtonTemplate quirk
		-- (references/BetterBags/.claude/rules/item-drawing.md's "Blue Glow
		-- Empty Slot Taint" section): clear the texture on the region itself,
		-- then hide it, rather than trying to clear it through SetNormalTexture.
		local normalTexture = btn:GetNormalTexture()
		if normalTexture then
			normalTexture:SetTexture(nil)
			normalTexture:Hide()
		end

		-- ConsolePort marker: biases reselection toward item slots over
		-- other node types when the cursor has to land somewhere arbitrary
		-- (frame reopen, no prior node) -- see ConsolePortNode's
		-- GetPriorityCandidate / TASKS.md task 2. Not a full nav graph
		-- (DESIGN.md invariant 5's graph module is still future work), just
		-- the fallback-net tagging invariant 5 already requires regardless.
		btn:SetAttribute("nodepriority", 1)

		slotPool[key] = btn
		return btn
	end

	local function AcquireLabel(key, fontTemplate)
		local fs = labelPool[key]
		if fs then return fs end

		fs = frame:CreateFontString(nil, "OVERLAY", fontTemplate)
		labelPool[key] = fs
		return fs
	end

	-- Section headers are collapsible (user request, 2026-08-17 -- "Old
	-- Stuff" especially, since it's the section most worth hiding once
	-- read). That makes them clickable/mouse-enabled, which is exactly the
	-- case TASKS.md task 1 flagged nodeignore as load-bearing for: a plain
	-- non-mouse-enabled FontString is excluded from ConsolePort's candidate
	-- scan automatically, but a real Button is not, so without nodeignore a
	-- collapsible header would become a valid up/down nav target from the
	-- item grid, breaking DESIGN.md invariant 1. Collapse state persists in
	-- SpeedyBagsDB.collapsedSections (initialized in SpeedyBags.lua's
	-- ADDON_LOADED handler -- that's the SavedVariables boundary, this
	-- trusts it's already a table by the time any view can be shown) and is
	-- shared between the bag view and the bank view, since a section means
	-- the same thing in both.
	local function AcquireHeaderButton(sectionName)
		local key = "header:"..sectionName
		local btn = headerPool[key]
		if btn then return btn end

		btn = CreateFrame("Button", nil, frame)
		btn:SetHeight(SECTION_HEADER_HEIGHT)
		btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		btn.Text:SetPoint("LEFT")
		btn:SetScript("OnClick", function()
			SpeedyBagsDB.collapsedSections[sectionName] = not SpeedyBagsDB.collapsedSections[sectionName]
			Refresh()
		end)
		btn:SetAttribute("nodeignore", true)

		headerPool[key] = btn
		return btn
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
	--
	-- Neither widget calls EnableMouse by default, so both are already
	-- excluded from ConsolePort's candidate scan (IsInteractive requires
	-- real mouse-enable) without needing nodeignore -- Junk opts back in
	-- below specifically because it's actionable (hover shows sell value).
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

	-- Right-to-left row of gold + whatever currencies the player has pinned
	-- via Blizzard's own "Show in Backpack" toggle (Currency.lua) -- no
	-- hardcoded currency list, so anything the user pins (event currencies,
	-- etc.) shows up here without an addon update. Fixed per-widget width,
	-- same cosmetic tradeoff as the subcategory blocks below (simpler than
	-- measuring text, can overflow on an unusually large number).
	--
	-- Icon size/font bumped up (user feedback, 2026-08-17: "icons are tiny
	-- AF") from the original inline-text-markup version's 12px/Small font.
	local ICON_SIZE = 20
	local BORDER_THICKNESS = 3
	local GOLD_WIDGET_WIDTH = 100
	local CURRENCY_WIDGET_WIDTH = 80
	local CURRENCY_GAP = 12

	local function AcquireCurrencyWidget(key)
		local w = currencyPool[key]
		if w then return w end

		w = CreateFrame("Button", nil, frame)
		w:SetHeight(CURRENCY_ROW_HEIGHT)
		w.Text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		w:SetScript("OnLeave", GameTooltip_Hide)
		currencyPool[key] = w
		return w
	end

	local function RenderCurrencyRow(y)
		local usedCurrency = {}
		local xRight = FRAME_WIDTH - MARGIN

		-- Gold keeps Blizzard's own multi-denomination coin markup
		-- (gold/silver/copper icons together via GetCoinTextureString) --
		-- it isn't a per-profession currency, so there's nothing to
		-- disambiguate with a border/tint the way the Moxie currencies
		-- need below.
		do
			local gold = AcquireCurrencyWidget("gold")
			usedCurrency["gold"] = true
			if gold.Icon then gold.Icon:Hide() end
			if gold.Border then gold.Border:Hide() end
			gold.Text:ClearAllPoints()
			gold.Text:SetPoint("RIGHT")
			gold.Text:SetText(C_CurrencyInfo.GetCoinTextureString(ns.Currency.gold))
			gold:SetWidth(GOLD_WIDGET_WIDTH)
			gold:ClearAllPoints()
			gold:SetPoint("TOPRIGHT", frame, "TOPLEFT", xRight, y)
			gold:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(C_CurrencyInfo.GetCoinTextureString(ns.Currency.gold))
				GameTooltip:Show()
			end)
			gold:Show()
			xRight = xRight - GOLD_WIDGET_WIDTH - CURRENCY_GAP
		end

		-- Real currencies: a real icon Texture (not an inline text-markup
		-- icon -- that shape can't be tinted/bordered) behind a colored
		-- border square. User feedback, 2026-08-17: two Artisan's Moxie
		-- currencies rendered as "the same gray icon twice", indistinguishable
		-- without hovering -- Currency.lua's professionColor (keyed by
		-- currencyID, thematic per profession: green for Alchemy's potions,
		-- forge-red for Blacksmithing, etc.) tints the border so each Moxie
		-- reads at a glance. Currencies with no mapped color (anything
		-- that isn't a tracked Moxie) get a neutral gray border instead of
		-- no border at all, so the treatment stays consistent across the row.
		for _, info in ipairs(ns.Currency.list) do
			local key = "cur:"..info.currencyTypesID
			local w = AcquireCurrencyWidget(key)
			usedCurrency[key] = true

			if not w.Icon then
				w.Border = w:CreateTexture(nil, "BACKGROUND")
				w.Icon = w:CreateTexture(nil, "ARTWORK")
				-- Crops the icon atlas's own border padding, same inset
				-- Baganator uses for this exact kind of currency icon.
				w.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end

			w.Border:SetSize(ICON_SIZE + BORDER_THICKNESS * 2, ICON_SIZE + BORDER_THICKNESS * 2)
			w.Border:ClearAllPoints()
			w.Border:SetPoint("RIGHT", w, "RIGHT")
			local color = ns.Currency.professionColor[info.currencyTypesID] or { 0.5, 0.5, 0.5 }
			w.Border:SetColorTexture(color[1], color[2], color[3], 0.9)
			w.Border:Show()

			w.Icon:SetSize(ICON_SIZE, ICON_SIZE)
			w.Icon:ClearAllPoints()
			w.Icon:SetPoint("CENTER", w.Border, "CENTER")
			w.Icon:SetTexture(info.iconFileID)
			w.Icon:Show()

			w.Text:ClearAllPoints()
			w.Text:SetPoint("RIGHT", w.Border, "LEFT", -4, 0)
			w.Text:SetText(info.quantity)

			w:SetWidth(CURRENCY_WIDGET_WIDTH)
			w:ClearAllPoints()
			w:SetPoint("TOPRIGHT", frame, "TOPLEFT", xRight, y)
			w:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetCurrencyByID(info.currencyTypesID)
				GameTooltip:Show()
			end)
			w:Show()

			xRight = xRight - CURRENCY_WIDGET_WIDTH - CURRENCY_GAP
		end

		for key, w in pairs(currencyPool) do
			if not usedCurrency[key] then w:Hide() end
		end

		return y - CURRENCY_ROW_HEIGHT
	end

	-- Renders one subcategory block (background + label + its items, wrapping
	-- within the block if there are more than SUBCAT_COLS) at (x, y). Returns
	-- the block's rendered height.
	local function RenderSubcategory(x, y, sectionName, label, entries, usedKeys, usedLabels, usedBGs)
		local rows = math.ceil(#entries / SUBCAT_COLS)
		local height = SUBCAT_LABEL_HEIGHT + rows * SLOT_SIZE + (rows - 1) * SLOT_PAD

		local groupKey = "sub:"..sectionName..":"..label

		local bg = AcquireGroupBackground(groupKey)
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 4, y + 4)
		bg:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", x + SUBCAT_WIDTH + 4, y - height - 4)
		bg:Show()
		usedBGs[groupKey] = true

		local fs = AcquireLabel(groupKey, "GameFontNormalSmall")
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
		fs:SetText(label)
		fs:Show()
		usedLabels[groupKey] = true

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

		return height
	end

	-- Renders one section (header + its subcategory blocks, wrapping to a new
	-- row of blocks at the frame edge) starting at y. Returns the y to
	-- continue at, unchanged if the section has nothing in it -- empty
	-- sections don't reserve space or show a header. A collapsed section
	-- still shows its header (so it can be expanded again) but reserves no
	-- further space for its contents.
	local function RenderSection(sectionName, bySubcat, y, usedKeys, usedLabels, usedBGs, usedHeaders)
		if not bySubcat or not next(bySubcat) then
			return y
		end

		local header = AcquireHeaderButton(sectionName)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN, y)
		header:SetWidth(FRAME_WIDTH - MARGIN * 2)
		local collapsed = SpeedyBagsDB.collapsedSections[sectionName]
		header.Text:SetText((collapsed and "> " or "v ")..(ns.SECTION_LABELS[sectionName] or sectionName))
		header:Show()
		usedHeaders["header:"..sectionName] = true
		y = y - SECTION_HEADER_HEIGHT

		if collapsed then
			return y
		end

		local x = MARGIN
		local rowHeight = 0
		for _, subcatName in ipairs(SortedKeys(bySubcat)) do
			if x > MARGIN and x + SUBCAT_WIDTH > FRAME_WIDTH - MARGIN then
				x = MARGIN
				y = y - rowHeight - SUBCAT_PAD_Y
				rowHeight = 0
			end
			local height = RenderSubcategory(x, y, sectionName, subcatName, bySubcat[subcatName], usedKeys, usedLabels, usedBGs)
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
	-- already pulled junk out into model.junkCount/junkValue rather than
	-- creating entries for it. In the bank view, junk sitting in the bank
	-- can't be sold from there directly -- this stays informational (a nudge
	-- to move it to bags) rather than actionable, same widget either way.
	local function RenderAggregateRow(y, usedLabels, model)
		local x = MARGIN

		if model.emptyCount > 0 then
			local fs = AcquireLabel("sub:Empty", "GameFontNormalSmall")
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
			fs:SetText("Empty")
			fs:Show()
			usedLabels["sub:Empty"] = true

			local btn = AcquireAggregateSlot("empty", opts.slotPrefix.."EmptySlot")
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
			btn.Count:SetText(model.emptyCount)
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

			local btn = AcquireAggregateSlot("junk", opts.slotPrefix.."JunkSlot")
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
			SetJunkVisual(btn, model.junkItems)
			btn.Count:SetText(model.junkCount > 0 and model.junkCount or "")
			btn:Show()

			-- The count alone doesn't say whether a vendor trip is worth it.
			-- Deliberately mouse-enabled (unlike Empty) so it stays a valid
			-- ConsolePort nav target -- it's actionable information, not a
			-- pure label, even though it isn't a sell button (yet).
			btn:EnableMouse(true)
			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Junk")
				if model.junkCount > 0 then
					GameTooltip:AddLine(C_CurrencyInfo.GetCoinTextureString(model.junkValue), 1, 1, 1)
				else
					GameTooltip:AddLine("Nothing to sell.", 0.6, 0.6, 0.6)
				end
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", GameTooltip_Hide)
		end

		return y - SUBCAT_LABEL_HEIGHT - SLOT_SIZE - SECTION_PAD_Y
	end

	-- Renders the current model state. Never scans bags itself -- that's
	-- model.Update's job; this only reacts to whatever the model already has.
	-- Currency row renders last, at the bottom of the frame (user request,
	-- 2026-08-17 -- an earlier pass put it at the top, under the title).
	function Refresh()
		if not frame:IsShown() then return end

		local model = opts.model
		local sections = GroupEntries(model)
		local usedKeys, usedLabels, usedBGs, usedHeaders = {}, {}, {}, {}
		local y = -(MARGIN + TITLE_HEIGHT)

		for _, sectionName in ipairs(ns.SECTION_ORDER) do
			y = RenderSection(sectionName, sections[sectionName], y, usedKeys, usedLabels, usedBGs, usedHeaders)
			if sectionName == "Equipment" then
				y = RenderAggregateRow(y, usedLabels, model)
			end
		end

		y = RenderCurrencyRow(y)

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
		for key, bg in pairs(bgPool) do
			if not usedBGs[key] then
				bg:Hide()
			end
		end
		for key, btn in pairs(headerPool) do
			if not usedHeaders[key] then
				btn:Hide()
			end
		end

		-- y already includes the top margin (the starting offset below); only
		-- the bottom margin needs adding here.
		frame:SetSize(FRAME_WIDTH, MARGIN - y)
	end

	local view = { Frame = frame }

	function view.Show()
		frame:Show()
		ns.Currency.Update()
		opts.model.Update()
	end

	function view.Hide()
		frame:Hide()
	end

	function view.Toggle()
		if frame:IsShown() then
			view.Hide()
		else
			view.Show()
		end
	end

	view.Refresh = Refresh

	-- The render layer is just one model listener; it renders whatever the
	-- model already has, whenever the model says something changed.
	opts.model.OnChanged(Refresh)

	return view
end

---------------------------------------------------------------
-- The two views: same machinery, different bag-ID list and frame.
---------------------------------------------------------------
ns.BagView = NewBagView({
	name = "SpeedyBagsFrame",
	title = "SpeedyBags",
	model = ns.Model,
	slotPrefix = "SpeedyBagsSlot",
	point = { "RIGHT", UIParent, "CENTER", -20, 0 },
})

ns.BankView = NewBagView({
	name = "SpeedyBagsBankFrame",
	title = "SpeedyBags: Bank",
	model = ns.BankModel,
	slotPrefix = "SpeedyBagsBankSlot",
	point = { "LEFT", UIParent, "CENTER", 20, 0 },
})

-- Kept for backward compatibility with SpeedyBags.lua's bag-toggle
-- overrides, which only ever mean the bag view, never the bank view.
ns.Frame = ns.BagView.Frame
ns.Show = ns.BagView.Show
ns.Hide = ns.BagView.Hide
ns.Toggle = ns.BagView.Toggle

-- Currency state is global (character/account), not bag-specific -- both
-- views show the same row, so both refresh on any currency change. Each
-- Refresh() already no-ops while its own frame is hidden.
ns.Currency.OnChanged(function()
	ns.BagView.Refresh()
	ns.BankView.Refresh()
end)
