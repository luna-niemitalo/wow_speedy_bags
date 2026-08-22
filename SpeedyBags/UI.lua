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
-- Gap between the scrollable content area and the currency row -- the
-- currency row is deliberately NOT part of the scrolled content (user
-- request: it's "more of a part of the frame than an actual element"), so
-- this is real fixed frame chrome, not a SUBCAT_PAD_Y-style content gap.
local CURRENCY_ROW_GAP = 6
-- Bank-view-only: real switchable tabs (Warband Bank / Personal Bank), one
-- group visible at a time -- see NewBagView's opts.groups. Replaced an
-- earlier same-session design that stacked both groups' full content at
-- once (corrected 2026-08-17, user correction: "this is why i wanted
-- personal bank and warband bank as separate tabs" / "I want them to go
-- to the bank that is selected" -- stacking both simultaneously left no
-- single "selected" bank for actions like Deposit Reagents to target).
-- Bag view has exactly one group and never shows this row at all. Shares
-- the currency row's own height/row (not a separately-reserved row above
-- it) -- user request, 2026-08-17: "put the buttons on the same row as
-- the currency."
local TAB_WIDTH = 140
local SECTION_HEADER_HEIGHT = 20
local SUBCAT_LABEL_HEIGHT = 16
local SUBCAT_COLS = 4 -- max items per row in one block -- fewer entries use fewer columns, see SubcatCols
local SUBCAT_PAD_X = 16 -- gap between adjacent column slots
local SUBCAT_PAD_Y = 14 -- gap between two blocks stacked in the same column
local SECTION_PAD_Y = 18 -- gap after a section before the next header

-- Full-width (SUBCAT_COLS-wide) subcategory block, not dynamically
-- measured against label text width -- simpler than GetStringWidth-based
-- wrapping, and "no need to make it super editable" per the user's own
-- framing. A long label can overflow its block visually; not a
-- correctness problem, just cosmetic. Still used as the design target for
-- how wide the content area is (below) -- a smaller block (SubcatCols)
-- takes less than this, it never takes more.
local SUBCAT_WIDTH = SUBCAT_COLS * SLOT_SIZE + (SUBCAT_COLS - 1) * SLOT_PAD

-- Room reserved on the right of the content area for
-- UIPanelScrollFrameTemplate's slider (NewBagView's scrollFrame) --
-- anchored 6px outside the scroll frame's own right edge, plus the bar's
-- own width. Reserved unconditionally (not just when a scrollbar is
-- actually showing) so the content area's width -- and therefore its
-- wrap point -- never shifts depending on whether this view currently has
-- enough content to scroll.
local SCROLLBAR_WIDTH = 30

-- Five fixed-position column SLOTS a section's subcategory blocks are
-- packed into (masonry, see RenderSection) -- not five max-width blocks
-- laid edge to edge in a row anymore (that was the original, simpler
-- design; replaced 2026-08-17 per the user's own report, with a real
-- masonry diagram: row-then-wrap left an entire following row of small
-- blocks stranded even when there was clearly room for them beside a
-- short column from the row above). A column's own x position is fixed;
-- what varies is how many (and how narrow) blocks end up stacked in it.
local SECTION_COLUMNS = 5
local CONTENT_WIDTH = SECTION_COLUMNS * SUBCAT_WIDTH + (SECTION_COLUMNS - 1) * SUBCAT_PAD_X
local FRAME_WIDTH = MARGIN * 2 + SCROLLBAR_WIDTH + CONTENT_WIDTH

-- Caps the outer window's height so it can never grow off-screen (the
-- bank view routinely has enough tabs/items to hit this) -- content
-- beyond it scrolls instead, per the user's own report of the bank view
-- overflowing. A plain constant, not derived from UIParent:GetHeight():
-- UIParent's own coordinate space already tracks the user's UI scale
-- setting, not raw screen pixels, so there's no more-correct dynamic
-- value to derive here without also reading that scale back out.
local MAX_VIEW_HEIGHT = 640

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
-- C_NewItems.IsNewItem -- we never call it, and this suppresses the flag
-- outright (RemoveNewItem + hide texture + stop both anims) rather than
-- ever reading it. Not just leaving it alone: it defaults to shown right
-- after a reload/relog/character-switch, when the client hasn't yet run
-- Blizzard's own bag-frame code that would normally clear it (opening the
-- default bag view, hovering items there -- ContainerFrameItemButtonMixin:
-- OnUpdate does this on hover, ContainerFrame.lua:1541) -- so every item
-- would show the glow at once instead of just genuinely-new ones. This is
-- also why the Recent row (Data.lua's NewRecentTracker) keeps its own
-- separate notion of "recently seen" rather than reading C_NewItems back
-- out here: RemoveNewItem below erases that signal on every single render,
-- before anything else could ever read it.
local function ClearNewItemGlow(btn, bagID, slot)
	C_NewItems.RemoveNewItem(bagID, slot)
	btn.NewItemTexture:Hide()
	btn.BattlepayItemTexture:Hide()
	if btn.flashAnim:IsPlaying() or btn.newitemglowAnim:IsPlaying() then
		btn.flashAnim:Stop()
		btn.newitemglowAnim:Stop()
	end
end

-- Shared stacked-icon look for both aggregate slots (Junk, Quest): matches
-- Plumber's actual LootUI_Main.lua SetMergedItem algorithm (grayscale-
-- darkened real item icons layered diagonally, one per item, up to
-- Data.lua's ICON_STACK_CAP) -- Plumber has no static "merged badge" asset
-- to copy, this is the real mechanism it uses for its own merged-loot
-- display, replicated here. An empty stack shows a persistent placeholder
-- instead (setEmptyIcon, caller-supplied -- Junk and Quest each have their
-- own idle badge), so the slot is never just blank, per the user's own
-- request for Junk specifically.
local STACK_OVERLAP = 0.15
local function SetStackedIconVisual(btn, items, setEmptyIcon)
	local n = #items

	if n == 0 then
		setEmptyIcon(btn.Icon)
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

		local item = items[i]
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

local function SetJunkVisual(btn, junkItems)
	SetStackedIconVisual(btn, junkItems, function(icon)
		icon:SetAtlas("bags-junkcoin", true)
		icon:SetVertexColor(0.4, 0.4, 0.4)
	end)
end

-- TEXTURE_ITEM_QUEST_BORDER is Blizzard's own global (FrameXMLBase/
-- Constants.lua) -- the same idle "this is quest-related" badge
-- ContainerFrameItemButtonMixin:UpdateQuestItem itself uses for a quest
-- item that isn't currently active, borrowed directly rather than picking
-- a new asset for the same meaning.
local function SetQuestVisual(btn, questItems)
	SetStackedIconVisual(btn, questItems, function(icon)
		icon:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
		icon:SetVertexColor(1, 1, 1)
	end)
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

-- Denser subcategories first (ties broken alphabetically, for a stable
-- order run to run), rather than pure alphabetical -- per the user's
-- "reasonable ordering / category compressing instead of alphabetical"
-- request. This also happens to pack better once blocks are dynamically
-- sized (RenderSection/SubcatCols below): placing the widest blocks first
-- means the smaller ones that follow are the ones filling whatever's left
-- in a row, rather than a wide block landing last and forcing an
-- otherwise-avoidable wrap.
local function OrderedSubcats(bySubcat)
	local keys = {}
	for k in pairs(bySubcat) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local countA, countB = #bySubcat[a], #bySubcat[b]
		if countA ~= countB then
			return countA > countB
		end
		return a < b
	end)
	return keys
end

-- All entries in a section, regardless of subcategory -- what a section
-- header's right-click transfer (AcquireHeaderButton) needs to move, since
-- it's scoped to the whole section, not one subcategory block.
local function FlattenEntries(bySubcat)
	local all = {}
	for _, entries in pairs(bySubcat) do
		for _, entry in ipairs(entries) do
			table.insert(all, entry)
		end
	end
	return all
end

-- A block with fewer entries than SUBCAT_COLS only needs that many
-- columns -- e.g. a lone Optional Reagent or a five-item Parts stack no
-- longer reserves a full SUBCAT_COLS-wide block's worth of empty space.
-- Derived straight from the entry count, not configured per subcategory,
-- per the user's own "we need to dynamically detect that" framing.
local function SubcatCols(entries)
	return math.max(1, math.min(SUBCAT_COLS, #entries))
end

-- Builds one independent view: its own frame, its own pooled widgets. The
-- bag window and the bank window are the same rendering machinery running
-- twice, per the user's "bank UI as a reflection of this" ask -- one
-- factory, not two copy-pasted files, so a future layout/category fix
-- never needs to be made twice.
--
-- A view renders one or more independent groups (opts.groups), each with
-- its own model and its own complete section/subcategory breakdown, but
-- only ONE group is ever actually shown at a time -- a single group never
-- shows a tab row at all (the bag view), more than one gets real
-- switchable tabs (the bank view: Warband Bank / Personal Bank), same
-- shape as Blizzard's own tabbed bank frame. Each bank tab has its OWN
-- model (ns.WarbandBankModel/ns.PersonalBankModel), not one merged scan --
-- corrected 2026-08-17 after the user pointed out that combining their
-- empty-slot counts was actively misleading (warband space is shared
-- across the account, personal space isn't). See Bank.lua's own header
-- comment for the full reasoning. An earlier same-session design showed
-- both groups' full content stacked simultaneously instead of behind
-- tabs -- corrected again, same day, once the user clarified they want
-- one selected bank at a time ("this is why i wanted personal bank and
-- warband bank as separate tabs" / "I want them to go to the bank that is
-- selected" -- stacking both left no single answer for what a bank-scoped
-- action like Deposit Reagents should target).
--
-- opts: { name, title, slotPrefix, point = {point, relPoint, x, y},
--         groups = { { key?, label?, model, bankType?, transferTargetBagIDs,
--                       currencyMode }, ... },
--         depositButton = bool }
--   group.key namespaces that group's per-character selected-tab state
--   (SpeedyBagsDB.selectedGroup) so bag/bank views don't collide -- unused
--   when there's only one group. group.label is the tab button's text
--   (irrelevant for a single-group view, which never shows a tab row).
--   group.bankType (Enum.BankType.*) is which bank the deposit-reagents
--   button targets when this group is selected -- bag-view-only opts
--   (opts.depositButton unset) never reads it. group.transferTargetBagIDs
--   is a function returning the bag-ID list right-click transfers should
--   send this group's items to. group.currencyMode picks what the
--   currency row shows while this group is selected -- see
--   RenderCurrencyRow.
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

	-- Forward-declared: the tab buttons' click handler (below) and several
	-- header/label click handlers further down all need to call Refresh to
	-- re-flow the layout, but Refresh itself is only defined near the
	-- bottom of this factory.
	local Refresh

	-- Real tab buttons, one per group, fixed chrome sharing the bottom
	-- currency row -- user request, 2026-08-17: "put the buttons on the
	-- same row as the currency" (an earlier same-session version gave tabs
	-- their own row stacked above it, per an even earlier placement
	-- request -- superseded once the user clarified they meant the row
	-- itself, not just "somewhere below"). Only reserved when there's more
	-- than one group to choose between; the bag view's single group never
	-- shows any tabs at all. SpeedyBagsDB.selectedGroup persists the
	-- choice per-view (keyed by opts.name), same SavedVariables boundary
	-- pattern as collapsedSections -- initialized in SpeedyBags.lua's
	-- ADDON_LOADED handler.
	local hasTabs = #opts.groups > 1

	local function SelectedGroupIndex()
		return SpeedyBagsDB.selectedGroup[opts.name] or 1
	end

	local function SelectedGroup()
		return opts.groups[SelectedGroupIndex()] or opts.groups[1]
	end

	local tabButtons = {}
	if hasTabs then
		for i, group in ipairs(opts.groups) do
			local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			btn:SetSize(TAB_WIDTH, CURRENCY_ROW_HEIGHT)
			btn:SetText(group.label)
			btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", MARGIN + (i - 1) * (TAB_WIDTH + 6), MARGIN)
			btn:SetScript("OnClick", function()
				SpeedyBagsDB.selectedGroup[opts.name] = i
				Refresh()
			end)
			tabButtons[i] = btn
		end
	end

	-- Disables (grays out) whichever tab is currently selected -- cheap,
	-- standard "you're already here" indicator via UIPanelButtonTemplate's
	-- own disabled state, no custom highlight texture needed. Called from
	-- Refresh() itself, not just the click handler, so it's also correct
	-- on the very first render (nothing was ever clicked yet).
	local function UpdateTabButtons()
		if not hasTabs then return end
		local selected = SelectedGroupIndex()
		for i, btn in ipairs(tabButtons) do
			btn:SetEnabled(i ~= selected)
		end
	end

	-- Everything below the title scrolls, EXCEPT the tab row and the
	-- currency row -- added
	-- so the bank view (which routinely has more items than the bag view)
	-- doesn't grow past MAX_VIEW_HEIGHT and off the bottom of the screen,
	-- per the user's own report. The currency row stays fixed frame chrome
	-- rather than joining the scrolled content, per the user's own
	-- framing ("it's more of a part of the frame than an actual element")
	-- -- gold/currency should always be visible regardless of scroll
	-- position, not something you can scroll past. UIPanelScrollFrameTemplate
	-- is Blizzard's soft-deprecated (in favor of the newer ScrollBox/View
	-- API) but still-shipped scroll widget -- kept here anyway since
	-- ScrollBox's element-virtualization is built for a uniform list of
	-- rows, not this frame's mixed-height flow layout (headers, variable-
	-- sized subcategory blocks, an aggregate row); a plain ScrollFrame
	-- over one freeform content child is the actual shape of what's
	-- needed. scrollBarHideable makes the whole slider/track disappear
	-- when there's nothing to scroll (ScrollFrame_OnScrollRangeChanged,
	-- see SecureScrollTemplates.lua) instead of sitting there permanently
	-- disabled -- the bag view usually doesn't need it at all.
	-- The template's own XML already wires OnMouseWheel to
	-- ScrollFrameTemplate_OnMouseWheel -- EnableMouseWheel is the one
	-- piece that isn't part of the template (a plain Frame attribute,
	-- required before OnMouseWheel fires at all, regardless of whether a
	-- handler is attached).
	local scrollFrame = CreateFrame("ScrollFrame", opts.name.."ScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scrollFrame.scrollBarHideable = true
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN, -(MARGIN + TITLE_HEIGHT))
	scrollFrame:SetPoint(
		"BOTTOMRIGHT", frame, "BOTTOMRIGHT",
		-(MARGIN + SCROLLBAR_WIDTH), MARGIN + CURRENCY_ROW_HEIGHT + CURRENCY_ROW_GAP
	)

	-- The actual content frame all rendered widgets below are parented to
	-- and positioned relative to -- coordinates within it are 0-based
	-- (content's own TOPLEFT), since the MARGIN/TITLE_HEIGHT offset above
	-- is already baked into scrollFrame's own anchor.
	local content = CreateFrame("Frame", opts.name.."Content", scrollFrame)
	content:SetPoint("TOPLEFT")
	content:SetWidth(CONTENT_WIDTH)
	content:SetHeight(1) -- resized every Refresh once real content height is known
	scrollFrame:SetScrollChild(content)

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
	-- Only one group is ever rendered at a time now (real tabs, see above),
	-- so these no longer need a per-group namespace in their keys the way
	-- they briefly did under the earlier stacked-groups design -- a group
	-- switch just reuses the same widgets for whichever group is now
	-- selected (Refresh sets fresh text/entries/points on them either way).
	local slotPool = {}
	local labelPool = {} -- aggregate-row labels (Recent/Empty/Junk/Quest), keyed by a string tag
	local subcatLabelPool = {} -- subcategory label BUTTONS (right-click transfer), keyed like bgPool
	local bgPool = {} -- subcategory group backgrounds, keyed the same way as their label
	local aggregateWidgets = {} -- "empty" / "junk" / "quest" -> widget
	local currencyPool = {} -- "gold" / "cur:<currencyTypesID>" / "warbandGold" / "personalGold" -> widget
	local headerPool = {} -- "header:<sectionName>" -> collapsible header button
	local nextSlotID = 0

	-- A subtle background per subcategory block (LUNA_NOTES.md), just enough
	-- lighter than the frame's own backdrop that adjacent groups read as
	-- visually separate without needing a per-group unique color.
	local function AcquireGroupBackground(key)
		local bg = bgPool[key]
		if bg then return bg end

		bg = content:CreateTexture(nil, "BORDER")
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
		btn = CreateFrame("ItemButton", opts.slotPrefix..nextSlotID, content, "ContainerFrameItemButtonTemplate")
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

	-- Aggregate-row labels only now (Recent/Empty/Junk/Quest) -- subcategory
	-- labels moved to AcquireSubcatLabelButton below, since those need to be
	-- real clickable Buttons (right-click transfer) and a bare FontString
	-- can't receive clicks at all.
	local function AcquireLabel(key, fontTemplate)
		local fs = labelPool[key]
		if fs then return fs end

		fs = content:CreateFontString(nil, "OVERLAY", fontTemplate)
		labelPool[key] = fs
		return fs
	end

	-- Right-click "move this whole category to the other view" (user
	-- request, 2026-08-17) -- ns.TransferEntries (Transfer.lua) does the
	-- actual work; this just wires the click and holds the (entries,
	-- targetBagIDs) it needs, refreshed on every render since which
	-- entries belong to a given subcategory changes over time (set as
	-- mutable fields on the pooled button rather than baked into the
	-- OnClick closure, which is only created once at Acquire time).
	local function AcquireSubcatLabelButton(key)
		local btn = subcatLabelPool[key]
		if btn then return btn end

		btn = CreateFrame("Button", nil, content)
		btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.Text:SetPoint("LEFT")
		btn:RegisterForClicks("RightButtonUp")
		btn:SetScript("OnClick", function(self)
			ns.TransferEntries(self.transferEntries, self.transferTargetBagIDs())
		end)
		-- Same reasoning as the section header below: being clickable
		-- makes this a valid geometric nav candidate otherwise (unlike a
		-- plain FontString), so it needs nodeignore explicitly.
		btn:SetAttribute("nodeignore", true)

		subcatLabelPool[key] = btn
		return btn
	end

	-- Section headers are collapsible (user request, 2026-08-17 -- "Old
	-- Stuff" especially, since it's the section most worth hiding once
	-- read) AND right-click transfers the whole section (user request,
	-- same day as the subcategory-label version above -- "categories *and*
	-- subcategories should be right clickable"). Being clickable/mouse-
	-- enabled is exactly the case TASKS.md task 1 flagged nodeignore as
	-- load-bearing for: a plain non-mouse-enabled FontString is excluded
	-- from ConsolePort's candidate scan automatically, but a real Button
	-- is not, so without nodeignore a collapsible header would become a
	-- valid up/down nav target from the item grid, breaking DESIGN.md
	-- invariant 1. Collapse state persists in SpeedyBagsDB.collapsedSections
	-- (initialized in SpeedyBags.lua's ADDON_LOADED handler -- that's the
	-- SavedVariables boundary, this trusts it's already a table by the
	-- time any view can be shown) and is shared between the bag view and
	-- the bank view (keyed by sectionName alone, not groupKey -- collapse
	-- state is about the section itself, not which bank it's showing in),
	-- since a section means the same thing everywhere. groupKey namespaces
	-- the pooled BUTTON only (headerPool's key), so two different groups'
	-- same-named sections (e.g. both banks' "Equipment") get their own
	-- widget while sharing one collapse flag.
	local function AcquireHeaderButton(groupKey, sectionName)
		local key = groupKey.."header:"..sectionName
		local btn = headerPool[key]
		if btn then return btn end

		btn = CreateFrame("Button", nil, content)
		btn:SetHeight(SECTION_HEADER_HEIGHT)
		btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		btn.Text:SetPoint("LEFT")
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				ns.TransferEntries(self.transferEntries, self.transferTargetBagIDs())
				return
			end
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

		btn = CreateFrame("Frame", frameName, content)
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

		-- Parented to frame, not content -- the currency row is fixed
		-- chrome, not scrolled content (see the scrollFrame comment above).
		w = CreateFrame("Button", nil, frame)
		w:SetHeight(CURRENCY_ROW_HEIGHT)
		w.Text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		w:SetScript("OnLeave", GameTooltip_Hide)
		currencyPool[key] = w
		return w
	end

	-- Fixed position (BOTTOMRIGHT of frame, not threaded through the
	-- section-render y cursor) -- the currency row lives outside the
	-- scrolled content entirely (see the scrollFrame comment above), so it
	-- has nothing to flow after.
	-- currencyMode = SelectedGroup().currencyMode -- "warbandGoldOnly" or
	-- "personalGoldOnly" (bank view) show just that bank's own money, not
	-- the bag view's full pinned-currency row -- added 2026-08-17 per the
	-- user's own reasoning: a bank can't hold any currency it doesn't
	-- actually, literally store, and none of Currency.lua's pinned
	-- currencies (Artisan's Mettle, Delve currencies, etc.) are bank
	-- content at all. Personal Bank still shows the character's own gold
	-- (not a separate pool the way Warband's deposited gold is -- there's
	-- nothing else stored there) since it's still useful context for
	-- what's currently on screen.
	local function RenderCurrencyRow(currencyMode)
		local usedCurrency = {}
		local xRight = FRAME_WIDTH - MARGIN

		if currencyMode == "warbandGoldOnly" or currencyMode == "personalGoldOnly" then
			local isWarband = currencyMode == "warbandGoldOnly"
			local key = isWarband and "warbandGold" or "personalGold"
			local label = isWarband and "Warband" or "Personal"
			local amount = isWarband and ns.GetWarbandBankGold() or ns.Currency.gold

			local gold = AcquireCurrencyWidget(key)
			usedCurrency[key] = true
			if gold.Icon then gold.Icon:Hide() end
			if gold.Border then gold.Border:Hide() end
			gold.Text:ClearAllPoints()
			gold.Text:SetPoint("RIGHT")
			gold.Text:SetText(label..": "..C_CurrencyInfo.GetCoinTextureString(amount))
			gold:SetWidth(GOLD_WIDGET_WIDTH + 70) -- wider: carries a "<Label>:" prefix too
			gold:ClearAllPoints()
			gold:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", xRight, MARGIN)
			gold:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(label.." gold")
				GameTooltip:AddLine(C_CurrencyInfo.GetCoinTextureString(amount), 1, 1, 1)
				GameTooltip:Show()
			end)
			gold:Show()

			for poolKey, w in pairs(currencyPool) do
				if not usedCurrency[poolKey] then w:Hide() end
			end
			return
		end

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
			gold:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", xRight, MARGIN)
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
			w:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", xRight, MARGIN)
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
	end

	-- Shared by RenderSubcategory and RenderRecentRow -- both put a real
	-- entry into a real item slot, they just differ in where. Positioning
	-- (SetPoint/Show) stays the caller's job since the two lay out
	-- differently (a grid vs. a single row).
	local function ConfigureItemSlot(btn, entry)
		local loc = entry.locations[1]
		btn:SetBagID(loc.bag)
		btn:SetID(loc.slot)
		ClearNewItemGlow(btn, loc.bag, loc.slot)
		btn:SetItemButtonTexture(entry.icon)
		btn:SetItemButtonQuality(entry.quality, entry.itemLink)
		btn:SetItemButtonCount(entry.count > 1 and entry.count or nil)
		SetEquipmentOverlay(btn, entry)
		-- Native mixin method (ContainerFrameItemButtonTemplate) -- same
		-- call Blizzard's own ContainerFrame.lua makes, so an active quest
		-- item gets its real bang/border overlay for free. Only active
		-- ones ever reach here (see Data.lua's Scan) -- inactive ones are
		-- pulled into the aggregate Quest slot instead. Falsy args on a
		-- non-quest entry hide it.
		btn:UpdateQuestItem(entry.isQuestItem, entry.questID, entry.isActiveQuestItem)
	end

	-- Renders one subcategory block (background + label + its items, wrapping
	-- within the block if there are more than cols) at (x, y). cols is
	-- SubcatCols(entries) -- the caller's job, since RenderSection needs the
	-- same number to decide whether this block fits the current row before
	-- calling this at all. groupKey namespaces the pooled background/label
	-- widgets (see NewBagView's header comment); transferTargetBagIDs is
	-- handed to the subcategory label for its right-click transfer. Returns
	-- the block's rendered width and height.
	local function RenderSubcategory(
		x, y, groupKey, sectionName, label, entries, cols, transferTargetBagIDs, usedKeys, usedSubcatLabels, usedBGs
	)
		local rows = math.ceil(#entries / cols)
		local width = cols * SLOT_SIZE + (cols - 1) * SLOT_PAD
		local height = SUBCAT_LABEL_HEIGHT + rows * SLOT_SIZE + (rows - 1) * SLOT_PAD

		local blockKey = groupKey.."sub:"..sectionName..":"..label

		local bg = AcquireGroupBackground(blockKey)
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", content, "TOPLEFT", x - 4, y + 4)
		bg:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", x + width + 4, y - height - 4)
		bg:Show()
		usedBGs[blockKey] = true

		local labelBtn = AcquireSubcatLabelButton(blockKey)
		labelBtn:ClearAllPoints()
		labelBtn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
		labelBtn:SetSize(width, SUBCAT_LABEL_HEIGHT)
		labelBtn.Text:SetText(label)
		labelBtn.transferEntries = entries
		labelBtn.transferTargetBagIDs = transferTargetBagIDs
		labelBtn:Show()
		usedSubcatLabels[blockKey] = true

		local itemY = y - SUBCAT_LABEL_HEIGHT
		for i, entry in ipairs(entries) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local btn = AcquireSlot(entry.key)
			usedKeys[entry.key] = true

			ConfigureItemSlot(btn, entry)

			btn:ClearAllPoints()
			btn:SetPoint(
				"TOPLEFT", content, "TOPLEFT",
				x + col * (SLOT_SIZE + SLOT_PAD),
				itemY - row * (SLOT_SIZE + SLOT_PAD)
			)
			btn:Show()
		end

		return width, height
	end

	-- Renders one section (header + its subcategory blocks, masonry-packed
	-- into SECTION_COLUMNS fixed-position column slots) starting at y.
	-- Returns the y to continue at, unchanged if the section has nothing in
	-- it -- empty sections don't reserve space or show a header. A
	-- collapsed section still shows its header (so it can be expanded
	-- again) but reserves no further space for its contents.
	--
	-- Masonry, not row-then-wrap (replaced 2026-08-17 per the user's own
	-- report + diagram): each subcategory block (already ordered
	-- densest-first by OrderedSubcats) goes into whichever column slot
	-- currently has the LEAST content, not the next slot in reading order.
	-- That's what lets a short block that would've been stranded at the
	-- start of a mostly-empty new row instead tuck in beside a short
	-- column from higher up -- exactly the "whole row would fit into the
	-- empty space below the columns above it" case the user pointed out.
	-- Column x-positions are fixed (SECTION_COLUMNS slots of SUBCAT_WIDTH
	-- each); a narrower block (SubcatCols) still only takes its own width
	-- within that slot, left-aligned -- keeps the "5 columns" the user
	-- asked to keep, while the packing itself is what actually changed.
	local function RenderSection(
		groupKey, sectionName, bySubcat, y, transferTargetBagIDs, usedKeys, usedSubcatLabels, usedBGs, usedHeaders
	)
		if not bySubcat or not next(bySubcat) then
			return y
		end

		local header = AcquireHeaderButton(groupKey, sectionName)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		header:SetWidth(CONTENT_WIDTH)
		local collapsed = SpeedyBagsDB.collapsedSections[sectionName]
		header.Text:SetText((collapsed and "> " or "v ")..(ns.SECTION_LABELS[sectionName] or sectionName))
		header.transferEntries = FlattenEntries(bySubcat)
		header.transferTargetBagIDs = transferTargetBagIDs
		header:Show()
		usedHeaders[groupKey.."header:"..sectionName] = true
		y = y - SECTION_HEADER_HEIGHT

		if collapsed then
			return y
		end

		local columnBottom = {}
		for col = 1, SECTION_COLUMNS do
			columnBottom[col] = y
		end

		for _, subcatName in ipairs(OrderedSubcats(bySubcat)) do
			local entries = bySubcat[subcatName]
			local cols = SubcatCols(entries)

			local shortestCol = 1
			for col = 2, SECTION_COLUMNS do
				if columnBottom[col] > columnBottom[shortestCol] then
					shortestCol = col
				end
			end

			local blockY = columnBottom[shortestCol]
			if blockY < y then
				-- Not the first block in this column -- leave a gap below
				-- whatever's already stacked there.
				blockY = blockY - SUBCAT_PAD_Y
			end
			local blockX = (shortestCol - 1) * (SUBCAT_WIDTH + SUBCAT_PAD_X)

			local _, height = RenderSubcategory(
				blockX, blockY, groupKey, sectionName, subcatName, entries, cols,
				transferTargetBagIDs, usedKeys, usedSubcatLabels, usedBGs
			)
			columnBottom[shortestCol] = blockY - height
		end

		local sectionBottom = y
		for col = 1, SECTION_COLUMNS do
			sectionBottom = math.min(sectionBottom, columnBottom[col])
		end
		return sectionBottom - SECTION_PAD_Y
	end

	-- Recent, Empty, and Junk aggregate widgets share one row, positioned
	-- between Equipment and Misc to match the user's existing Baganator
	-- layout, which puts its Recent/Empty row there deliberately for
	-- ConsolePort nav reasons -- worth revisiting once our own nav-graph
	-- module (TASKS.md task 1) is real. Junk is never rendered as
	-- individual slots (DESIGN.md invariant 3) -- Data.lua's Scan already
	-- pulled junk out into model.junkCount/junkValue rather than creating
	-- entries for it. In the bank view, junk sitting in the bank can't be
	-- sold from there directly -- this stays informational (a nudge to
	-- move it to bags) rather than actionable, same widget either way.
	local function RenderAggregateRow(y, groupKey, usedKeys, usedLabels, model)
		local x = 0

		-- Recent uses real item slots (AcquireSlot), not the aggregate-
		-- badge shape Junk/Quest use -- these are individually actionable
		-- items you'd actually want to click, not a collapsed count. Keyed
		-- "recent:"..entry.key rather than entry.key itself (entry.key is
		-- already globally unique, so no groupKey needed either): the same
		-- item can legitimately also be showing in its normal category grid
		-- right now, and that's a different widget (a real WoW Frame can
		-- only have one position at a time) even though both point at the
		-- same bag slot underneath.
		if #model.recentEntries > 0 then
			local fs = AcquireLabel(groupKey.."sub:Recent", "GameFontNormalSmall")
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
			fs:SetText("Recent")
			fs:Show()
			usedLabels[groupKey.."sub:Recent"] = true

			local itemY = y - SUBCAT_LABEL_HEIGHT
			for i, entry in ipairs(model.recentEntries) do
				local key = "recent:"..entry.key
				local btn = AcquireSlot(key)
				usedKeys[key] = true

				ConfigureItemSlot(btn, entry)

				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", content, "TOPLEFT", x + (i - 1) * (SLOT_SIZE + SLOT_PAD), itemY)
				btn:Show()
			end

			x = x + #model.recentEntries * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD + SUBCAT_PAD_X
		end

		if model.emptyCount > 0 then
			local fs = AcquireLabel(groupKey.."sub:Empty", "GameFontNormalSmall")
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
			fs:SetText("Empty")
			fs:Show()
			usedLabels[groupKey.."sub:Empty"] = true

			local btn = AcquireAggregateSlot(groupKey.."empty", opts.slotPrefix..groupKey.."EmptySlot")
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
			btn.Count:SetText(model.emptyCount)
			btn:Show()

			x = x + SLOT_SIZE + SUBCAT_PAD_X
		elseif aggregateWidgets[groupKey.."empty"] then
			aggregateWidgets[groupKey.."empty"]:Hide()
		end

		-- Always rendered, even with zero junk -- a persistent slot (see
		-- SetJunkVisual) rather than popping in and out of the layout.
		do
			local fs = AcquireLabel(groupKey.."sub:Junk", "GameFontNormalSmall")
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
			fs:SetText("Junk")
			fs:Show()
			usedLabels[groupKey.."sub:Junk"] = true

			local btn = AcquireAggregateSlot(groupKey.."junk", opts.slotPrefix..groupKey.."JunkSlot")
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
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

			x = x + SLOT_SIZE + SUBCAT_PAD_X
		end

		-- Inactive quest items only (Data.lua's Scan never counts an
		-- active one here -- that stays a normal, fully visible entry
		-- with its own native quest-bang overlay instead). Conditionally
		-- shown, like Empty, rather than a permanent fixture like Junk --
		-- most bags have none of these most of the time.
		if model.questCount > 0 then
			local fs = AcquireLabel(groupKey.."sub:Quest", "GameFontNormalSmall")
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
			fs:SetText("Quest")
			fs:Show()
			usedLabels[groupKey.."sub:Quest"] = true

			local btn = AcquireAggregateSlot(groupKey.."quest", opts.slotPrefix..groupKey.."QuestSlot")
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - SUBCAT_LABEL_HEIGHT)
			SetQuestVisual(btn, model.questItems)
			btn.Count:SetText(model.questCount)
			btn:Show()
		elseif aggregateWidgets[groupKey.."quest"] then
			aggregateWidgets[groupKey.."quest"]:Hide()
		end

		return y - SUBCAT_LABEL_HEIGHT - SLOT_SIZE - SECTION_PAD_Y
	end

	-- Renders the CURRENTLY SELECTED group only (SelectedGroup()) -- real
	-- tabs, not every group stacked (see NewBagView's own header comment).
	-- Never scans bags itself -- that's the group's model.Update()'s job;
	-- this only reacts to whatever it already has. Currency row renders
	-- separately (RenderCurrencyRow, called below) -- fixed frame chrome
	-- outside the scrolled content, not part of this y-cursor flow at all
	-- (user request: it's "more of a part of the frame than an actual
	-- element").
	function Refresh()
		if not frame:IsShown() then return end

		UpdateTabButtons()
		local group = SelectedGroup()

		local usedKeys, usedLabels, usedSubcatLabels, usedBGs, usedHeaders = {}, {}, {}, {}, {}
		-- 0-based: content's own TOPLEFT already sits at the scrolled
		-- viewport's top -- the MARGIN/TITLE_HEIGHT/tab-row offset that
		-- used to start this cursor is now baked into scrollFrame's own
		-- anchor instead (see NewBagView).
		local y = 0

		local sections = GroupEntries(group.model)
		for _, sectionName in ipairs(ns.SECTION_ORDER) do
			y = RenderSection(
				"", sectionName, sections[sectionName], y, group.transferTargetBagIDs,
				usedKeys, usedSubcatLabels, usedBGs, usedHeaders
			)
			if sectionName == "Equipment" then
				y = RenderAggregateRow(y, "", usedKeys, usedLabels, group.model)
			end
		end

		RenderCurrencyRow(group.currencyMode)

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
		for key, btn in pairs(subcatLabelPool) do
			if not usedSubcatLabels[key] then
				btn:Hide()
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

		-- content's true height (-y) can exceed the outer frame's, once
		-- capped below -- that's exactly what makes the scrollFrame
		-- actually need to scroll. The outer frame stays snug to its
		-- natural size (title + tab row + content + currency row) when
		-- everything fits, same "no wasted space" behavior as before the
		-- scrollFrame existed, just now clamped at MAX_VIEW_HEIGHT instead
		-- of growing without bound.
		local contentHeight = -y
		content:SetSize(CONTENT_WIDTH, math.max(contentHeight, 1))

		local naturalHeight = MARGIN * 2 + TITLE_HEIGHT + contentHeight + CURRENCY_ROW_GAP + CURRENCY_ROW_HEIGHT
		frame:SetSize(FRAME_WIDTH, math.min(naturalHeight, MAX_VIEW_HEIGHT))
	end

	-- Equivalent to Blizzard's old "Deposit Reagents" button, which
	-- disappeared once HideDefaultBank (Bank.lua) suppressed the default
	-- bank frame entirely -- the user asked for it back somewhere in this
	-- chrome. Same bottom row as the tab buttons and the currency display
	-- (user request, 2026-08-17: "put the buttons on the same row as the
	-- currency"), sitting right after the tabs -- opts.depositButton is
	-- only ever set alongside multiple groups (the bank view), so there's
	-- always a real tab row to sit next to here. Bag-view-only opts
	-- (opts.depositButton unset there) never creates this at all.
	--
	-- Targets SelectedGroup().bankType specifically -- corrected 2026-08-17,
	-- user correction: an earlier version tried both bank types
	-- unconditionally ("whichever one has the flag"), but the user pointed
	-- out both of their banks actually have a reagent-deposit tab
	-- configured, so "both" was genuinely ambiguous, not just apparently
	-- so -- they want it to deposit into whichever bank is currently
	-- selected (the same reason real tabs replaced the earlier stacked-
	-- groups design above).
	if opts.depositButton then
		local depositButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		depositButton:SetSize(140, CURRENCY_ROW_HEIGHT)
		depositButton:SetText("Deposit Reagents")
		depositButton:SetPoint(
			"BOTTOMLEFT", frame, "BOTTOMLEFT", MARGIN + #opts.groups * (TAB_WIDTH + 6), MARGIN
		)
		depositButton:SetScript("OnClick", function()
			ns.DepositReagents(SelectedGroup().bankType)
		end)
		depositButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Deposit Reagents")
			GameTooltip:AddLine("Deposits into "..SelectedGroup().label..".", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		depositButton:SetScript("OnLeave", GameTooltip_Hide)
	end

	local view = { Frame = frame }

	-- Does NOT re-scan on open (corrected 2026-08-17, user correction) --
	-- every group's model.Update() already runs continuously in the
	-- background regardless of this frame's visibility (SpeedyBags.lua's
	-- MakeScheduler), so model.entries is already current by the time this
	-- runs. Show() only has to pay for the one thing that WAS actually
	-- skipped while hidden: an actual render pass (Refresh's own
	-- IsShown() guard blocked every Refresh call that happened while
	-- closed). Same reasoning for Currency.lua -- already updates on its
	-- own PLAYER_MONEY/CURRENCY_DISPLAY_UPDATE events regardless of
	-- visibility, so re-forcing it here would be the same redundant work
	-- this fix is about removing.
	function view.Show()
		frame:Show()
		Refresh()
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

	-- Debounces bursts of model changes (mass loot/vendor/mail/unbox --
	-- each one firing its own model.Update() -> OnChanged) into a single
	-- trailing Refresh -- added 2026-08-17, user report: "masonry recomputes
	-- on every item change and it's massively slow." Refresh's own full
	-- masonry pack over every section/subcategory (RenderSection) is a real,
	-- unavoidable-for-now cost (the diff-based "patch only affected slots"
	-- render is DESIGN.md's stated target architecture, gated on task 3's
	-- still-open event-granularity investigation -- not something to build
	-- here). Coalescing repeated calls into one, the same way
	-- SpeedyBags.lua's MakeScheduler already coalesces bursts of raw
	-- BAG_UPDATE events into one model.Update(), at least keeps a rapid
	-- multi-item event burst from paying that full cost once per item
	-- instead of once per burst. 0.1s (not 0, like MakeScheduler) is
	-- deliberately longer than a single frame -- MakeScheduler's C_Timer.
	-- After(0, ...) only coalesces events landing in the exact same frame,
	-- which a loot/mail/vendor burst spread across several frames would
	-- still miss.
	local refreshPending
	local function ScheduleRefresh()
		if refreshPending then
			refreshPending:Cancel()
		end
		refreshPending = C_Timer.NewTimer(0.1, function()
			refreshPending = nil
			Refresh()
		end)
	end

	-- The render layer is just one model listener per group; it renders
	-- whatever each group's model already has, whenever that model says
	-- something changed.
	for _, group in ipairs(opts.groups) do
		group.model.OnChanged(ScheduleRefresh)
	end

	return view
end

---------------------------------------------------------------
-- The two views: same machinery, different groups/frame.
---------------------------------------------------------------
ns.BagView = NewBagView({
	name = "SpeedyBagsFrame",
	title = "SpeedyBags",
	groups = {
		{
			model = ns.Model,
			-- Warband bank by default, matching Bank.lua's own "warband
			-- bank listed first" precedent -- only actually succeeds
			-- while at a banker (Blizzard's own restriction on
			-- manipulating unopened bank slots, not something SpeedyBags
			-- enforces itself); TransferEntries just reports "no space"
			-- via UIErrorsFrame if the bank isn't open.
			transferTargetBagIDs = ns.GetWarbandBankBagIDs,
			currencyMode = "full",
		},
	},
	slotPrefix = "SpeedyBagsSlot",
	point = { "RIGHT", UIParent, "CENTER", -20, 0 },
})

ns.BankView = NewBagView({
	name = "SpeedyBagsBankFrame",
	title = "SpeedyBags: Bank",
	groups = {
		{
			key = "warband",
			label = "Warband Bank",
			model = ns.WarbandBankModel,
			bankType = Enum.BankType.Account,
			transferTargetBagIDs = function() return ns.BAG_IDS end,
			currencyMode = "warbandGoldOnly",
		},
		{
			key = "personal",
			label = "Personal Bank",
			model = ns.PersonalBankModel,
			bankType = Enum.BankType.Character,
			transferTargetBagIDs = function() return ns.BAG_IDS end,
			currencyMode = "personalGoldOnly",
		},
	},
	slotPrefix = "SpeedyBagsBankSlot",
	point = { "LEFT", UIParent, "CENTER", 20, 0 },
	depositButton = true,
})

-- Kept for backward compatibility with SpeedyBags.lua's bag-toggle
-- overrides, which only ever mean the bag view, never the bank view.
ns.Frame = ns.BagView.Frame
ns.Show = ns.BagView.Show
ns.Hide = ns.BagView.Hide
ns.Toggle = ns.BagView.Toggle

-- Character gold/pinned-currency changes only actually affect the bag
-- view's currency row now (the bank view's is warbandGoldOnly, driven by
-- ACCOUNT_MONEY instead -- see SpeedyBags.lua) -- refreshing both here is
-- harmless (Refresh() no-ops while its own frame is hidden), just not
-- load-bearing for the bank view specifically anymore.
ns.Currency.OnChanged(function()
	ns.BagView.Refresh()
	ns.BankView.Refresh()
end)
