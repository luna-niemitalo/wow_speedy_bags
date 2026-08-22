# CLAUDE.md — wow_speedy_bags

Global rules apply (`~/.claude/CLAUDE.md`). Nix conventions: `.claude/rules/nix.md`.
Read `DESIGN.md` before any structural change.

## Purpose

The near-term goal is **not** a comprehensive, feature-complete bag addon — it's a
small, readable, understandable framework to build and edit on, as the deliberate
opposite of the 20-years-of-accretion codebases every reference addon in
`references/` has become. Every addition should keep reading as a handful of
single-purpose files a person can hold in their head, not accumulate toward that same
mess. The controller nav order and non-blocking, event-driven bag updates
(`DESIGN.md`'s invariants) are the eventual differentiators, built incrementally on
top of this framework — not yet present.

## Status

- **Current**: a working, categorized bag UI with a real junk slot, Pawn
  upgrade-advisor integration, a bank view (Personal/Warband kept visually
  distinct, each with its own right-click bulk transfer), a currency row, and
  ConsolePort nav markers in `SpeedyBags/` — nine files, each one job:
  - `Data.lua` — `Scan(bagIDs)` reads a given combined bag-ID list into display
    entries, merging same-itemID non-equipment slots into one visual stack (even
    where the real inventory wouldn't stack them) and counting empty slots. Each
    new entry is classified via `ns.Categorize` (Categories.lua) into a
    `section`/`subcategory`. An *inactive* quest item (`C_Container.
    GetContainerItemQuestInfo`'s `isQuestItem` true, `isActive` false — nothing to
    Use yet) is pulled out into an aggregate `questCount`/`questItems` instead of
    becoming an entry, same shape as Junk; an *active* one stays a normal entry
    (`isQuestItem`/`questID`/`isActiveQuestItem` on it, for `UI.lua`'s native
    quest-bang overlay). `NewRecentTracker()` gives each model its own session-only
    "recently seen" notion (a key that's new to that model's scan history, or whose
    count went up) — can't reuse Blizzard's own `C_NewItems.IsNewItem`, since
    `UI.lua`'s `ClearNewItemGlow` already erases that flag every render; results
    feed `model.recentEntries` (capped, newest-first, self-expiring after
    `RECENT_WINDOW_SECONDS`). `ns.NewModel(getBagIDs)` builds a model holding the
    current scanned state and an `OnChanged` listener list — the only thing that
    mutates state or triggers a rescan; `ns.Model` (bag view, static `ns.BAG_IDS` —
    Backpack + Bag_1-4 + ReagentBag), `Bank.lua`'s `ns.PersonalBankModel`, and
    `Bank.lua`'s `ns.WarbandBankModel` (bank view's two independent groups — see
    `Bank.lua` and `UI.lua`'s entries below for why they're not one merged scan)
    are all instances of it, one scanner shared across every view.
  - `Currency.lua` — `ns.Currency.Update()` reads gold (`GetMoney()`) plus whatever
    currencies the player has pinned via Blizzard's own "Show in Backpack" toggle
    (`C_CurrencyInfo.GetBackpackCurrencyInfo`), refreshed on `PLAYER_MONEY`/
    `CURRENCY_DISPLAY_UPDATE` and immediately on Blizzard's own
    `TokenFrame.OnTokenWatchChanged` callback. No hardcoded currency list for most
    of the user's wishlist — several named TWW currencies have no IDs verifiable
    from this project's offline reference mirrors, so this reuses Blizzard's real
    pinning mechanism instead of guessing (user-directed decision, 2026-08-17;
    same approach as Baganator's `CurrencyBlizzardTracking.lua`). One exception:
    `AutoPinProfessionMoxie` auto-pins the Artisan's Moxie currency matching each
    trained profession (`C_TradeSkillUI.GetAllProfessionTradeSkillLines()`'s
    locale-independent skillLine IDs mapped to currency IDs the user supplied
    directly for two professions, the rest looked up to complete the verified
    3256–3266 pattern), on `PLAYER_LOGIN`/`SKILL_LINES_CHANGED`.
  - `Bank.lua` — `ns.GetPersonalBankBagIDs()`/`ns.GetWarbandBankBagIDs()` each
    drive one of the two bank models off `C_Bank.FetchPurchasedBankTabIDs`
    (`Enum.BankType.Character`/`Enum.BankType.Account`), gated on actual
    tab-purchase state rather than scanning a fixed tab-ID range; never *reads*
    state back off the `BankFrame`/`BankPanel` globals — see DESIGN.md's
    bank-taint note. Kept as two separate models rather than one merged list
    (corrected 2026-08-17, user report) — combining their empty-slot counts
    into one number was actively misleading (warband space is shared across
    every character on the account, personal space isn't accessible to any of
    them). `ns.GetWarbandBankGold()` (`C_Bank.FetchDepositedMoney`) reads
    Warband Bank's own separate deposited-gold pool, distinct from the
    player's own `GetMoney()` — feeds `UI.lua`'s bank-only currency row.
    `ns.DepositReagents()` calls `C_Bank.AutoDepositItemsIntoBank` against both
    bank types (each a no-op if that type has no auto-deposit-flagged tab) —
    the modern equivalent of Blizzard's old "Deposit Reagents" button, restored
    as a real button in `UI.lua`'s chrome since suppressing the default bank
    frame (below) took the original away. `HideDefaultBank` (called once at
    load) does structurally touch `BankFrame` — reparenting it onto a hidden
    frame and clearing its `OnHide`/`OnEvent`/`OnShow` scripts, matching
    Baganator's own real production code exactly — so SpeedyBags' bank view is
    the only one the player sees. No separate Reagent Bank handling needed:
    the modern client folded it into regular character-bank tabs.
  - `Categories.lua` — pure classification: itemClassID/subClassID/equip-slot/bind
    status/expansionID in, `{section, subcategory}` out. No frames, no widgets. Four
    sections (Crafting, Equipment, Misc, Old Stuff) matching the user's own working
    Baganator layout, described directly rather than reverse-engineered from
    Baganator's own (Syndicator-gated, deliberately unused) category engine.
  - `Junk.lua` — `ns.IsJunk(itemID, quality, isBound, isEquipment)`. Soft-integrates
    with Leatrix_Plus (`_G.LeaPlusDB`, read directly, verified against its real
    installed source, not guessed) when present, replicating its actual sell rule
    (quality Poor + sellable, minus its exclude list / Keeper Ta'hult / grey-gear
    settings) so SpeedyBags' Junk slot agrees with what Leatrix_Plus will actually
    vendor; falls back to Blizzard's bare Poor-quality rule otherwise. This is a
    deliberate exception to "no external dependencies" — see DESIGN.md's external-
    integration note: that rule targets other bag addons and Syndicator specifically,
    not complementary QoL addons doing something genuinely different.
  - `Pawn.lua` — same soft-integration pattern as `Junk.lua`, this time with Pawn's
    own first-party third-party-bag API (`PawnRegisterThirdPartyBag`,
    `PawnShouldItemLinkHaveUpgradeArrow`) — Pawn's real source explicitly documents
    this contract for bag addons, nothing to reverse-engineer. `ns.IsUpgrade(link)`
    returns true/false/nil (nil = Pawn hasn't resolved it yet, throttled); `Data.lua`
    schedules one deferred re-scan when that happens instead of leaving arrows stuck
    unresolved.
  - `Transfer.lua` — `ns.TransferEntries(entries, targetBagIDs)`, the right-click
    "move this category" action `UI.lua`'s section headers and subcategory labels
    both call. `C_Container.PickupContainerItem` pickup-then-place pairs, same
    mechanism a normal click-drag performs — verified safe against Baganator's
    own real, shipped `Transfers/FromBagsToBags.lua` (`PickupContainerItem` is
    NOT itself protected, only `UseContainerItem` is, see DESIGN.md and
    `Pawn.lua`'s own note on the same fact). Guarded on `InCombatLockdown()`.
  - `UI.lua` — `NewBagView(opts)` is a factory, not a single frame: it builds one
    independent view (its own frame, its own pooled widgets) from
    `opts.name`/`opts.slotPrefix`/`opts.point`/`opts.groups`. `ns.BagView` (one
    ungrouped group, `ns.Model`) and `ns.BankView` (two groups — `ns.WarbandBankModel`
    labeled "Warband Bank", `ns.PersonalBankModel` labeled "Personal Bank") are
    both built from it — one rendering implementation for both windows, not two
    copy-pasted files, per the user's "bank UI as a reflection of this" ask. A
    view can render more than one independent group now (corrected 2026-08-17,
    user report): each group gets its own complete section/subcategory
    breakdown and its own super-header when labeled, rather than the bank's two
    models being flattened into one merged set of sections — every pooled
    widget key is namespaced by `groupKey` so two groups' same-named sections
    (both banks have an "Equipment" section) get separate widgets. Everything
    below the title renders into a `content` frame inside a real `ScrollFrame`
    (`UIPanelScrollFrameTemplate`), not directly into the outer frame — added
    2026-08-17 after the bank view visibly overflowed the screen (user
    screenshot). The outer frame still sizes snugly to its natural content height
    when everything fits, now clamped at `MAX_VIEW_HEIGHT` instead of growing
    without bound; content beyond that scrolls, with the slider auto-hiding itself
    (`scrollBarHideable`) when there's nothing to scroll. The currency row is the
    one exception — parented to the outer `frame` directly and anchored fixed to
    its bottom, deliberately *not* part of the scrolled content (user: "it's more
    of a part of the frame than an actual element"), so gold/currency stays
    visible regardless of scroll position; each group's own `currencyMode`
    picks what it shows while that group is the selected tab — `"full"`
    (bag view's one group: gold + `Currency.lua`'s pinned currencies),
    `"warbandGoldOnly"` (Warband Bank's own deposited-gold balance,
    `Bank.lua`'s `ns.GetWarbandBankGold`), or `"personalGoldOnly"`
    (Personal Bank: the character's own gold, same value as the bag view's
    — Personal Bank has no separate currency store of its own) — per the
    user's own reasoning, a bank can't hold currency it doesn't actually
    store, and none of the pinned currencies are bank content at all.
    `opts.depositButton` (bank view only) adds a real button calling
    `ns.DepositReagents(SelectedGroup().bankType)` — targets whichever bank
    is the currently SELECTED tab specifically (corrected 2026-08-17: an
    earlier version tried both bank types unconditionally, which turned out
    genuinely ambiguous once the user reported having a reagent-deposit tab
    configured on both banks) — bottom-left, mirroring the currency row's
    bottom-right. Sectioned,
    flow-wrapped rendering: collapsible section headers (`AcquireHeaderButton` —
    real `Button`s, left-click toggles `SpeedyBagsDB.collapsedSections`
    (persisted, shared across every group/view since a section means the same
    thing everywhere), right-click transfers every entry in that section via
    `Transfer.lua`), subcategory label+item blocks wrapping at the content edge
    — the label itself is now a real `Button` too (`AcquireSubcatLabelButton`,
    not a bare `FontString`), right-click transferring just that block
    (user request, 2026-08-17: "categories *and* subcategories should be right
    clickable to transfer all of the items from that category" — the bag
    view's target is `ns.GetWarbandBankBagIDs`, matching the "default to
    warband bank" precedent; both bank groups target `ns.BAG_IDS`). Blocks are
    masonry-packed into `SECTION_COLUMNS` (5) fixed-position column slots, not
    row-then-wrapped (replaced 2026-08-17, user report + diagram: row-wrapping
    left an entire following row of small blocks stranded even when there was
    room for them beside a short column higher up) — `OrderedSubcats` orders
    blocks densest-first, and each goes into whichever column currently has
    the least content, not the next slot in reading order; `SubcatCols(entries)`
    still caps each block's own width at its entry count (not always the
    column's full width) so a handful of Parts/Optional-Reagent-style items
    doesn't force a wider slot than it needs — an aggregate row (Recent row of
    real clickable item slots + Empty count + Junk count/sell-value tooltip +
    Quest count) positioned between Equipment and Misc within each group
    (matching the reference layout's ConsolePort-nav-motivated placement), all
    pooled and keyed by `entry.key` (stable item identity — itemID for merged
    stacks, item GUID for equipment) so scan-order churn can't silently reassign
    a widget to a different item; a Recent-row slot for an item also showing in
    its normal category grid gets its own separate pooled widget (keyed
    `"recent:"..entry.key`), since one real WoW Frame can't occupy two
    positions at once even for the same underlying bag slot. Item slots inherit
    Blizzard's real `ContainerFrameItemButtonTemplate` so click-to-use/pickup
    run as untainted Blizzard code — confirmed working in-game (§ Resume).
    Equipment slots also show Pawn's `UpgradeIcon` (a native template region, no
    new texture) and item level (`C_Item.GetDetailedItemLevelInfo`, accounts for
    upgrades unlike the static base ilvl); an active quest item gets Blizzard's
    own quest-bang/border overlay via `btn:UpdateQuestItem(...)`, the same
    native call `ContainerFrame.lua` itself makes. New-item glow is explicitly
    suppressed (`ClearNewItemGlow`) since we never call Blizzard's own
    `UpdateNewItem` and it would otherwise default to shown on everything after
    a reload; the default button chrome (`NormalTexture`) is cleared too,
    keeping only the quality-colored `IconBorder` — both real bugs the user hit
    in-game, not anticipated. Each view's main content frame carries
    `nodeignore` (so its own drag-enabled backdrop isn't itself a ConsolePort nav
    candidate); item slots carry `nodepriority = 1` (reselection bias toward real
    items); collapsible/transferable section headers and subcategory labels
    carry `nodeignore` too, since being clickable makes them a valid geometric
    nav candidate otherwise (unlike plain `FontString` labels) — all
    fallback-net tagging DESIGN.md invariant 5 requires regardless of whether
    the hand-authored nav-graph module exists yet (it doesn't — see TASKS.md
    task 1). Renders only from its bound models' already-scanned state; never
    scans bags itself.
  - `SpeedyBags.lua` — event wiring: `BAG_UPDATE`/bank-slot-changed events are each
    coalesced via `C_Timer.After(0, ...)` (one shared `MakeScheduler` factory; bag,
    personal bank, and warband bank each get their own debounced instance, the
    latter two sharing the bank view's frame) into a single deferred
    `model.Update()` rather than scanning inline in the event handler (data-mutation
    and rendering are deliberately decoupled, per invariant 4's intent, though task
    3 itself is still open). `PLAYERBANKSLOTS_CHANGED`/
    `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` route to just the one bank model each
    actually affects (Character/Account respectively); `BANK_TABS_CHANGED` (a tab
    purchased) doesn't say which type, so it updates both. The default bag toggle
    (`ToggleBackpack`/`ToggleAllBags`/etc.) is redefined to open the bag view.
    `BANKFRAME_OPENED`/`BANKFRAME_CLOSED` show/hide the bank view — the only one
    visible, since `Bank.lua`'s `HideDefaultBank` already suppressed Blizzard's
    own. `PLAYER_MONEY`/`CURRENCY_DISPLAY_UPDATE` drive `Currency.lua`;
    `ACCOUNT_MONEY` (Warband Bank's own separate gold pool, not covered by
    `PLAYER_MONEY`) refreshes the bank view directly. `ADDON_LOADED` also seeds
    `SpeedyBagsDB.collapsedSections` (the SavedVariables boundary for `UI.lua`'s
    collapsible headers).
  - Also present: `nix/flake.nix` dev shell, `scripts/fetch-warcraft-wiki.nu` (a real,
    re-runnable tool, not a one-off), project docs (`DESIGN.md`, `TASKS.md`,
    `TODO.md`), and `references/` (gitignored, see `references/README.md`).
  - **Deliberately not yet in place**: ConsolePort hand-authored nav-graph
    integration (the fallback-net `nodeignore`/`nodepriority` tagging is in — see
    `UI.lua`'s entry above — but there's still no `graph[node][direction]` module,
    so nav is pure ConsolePortNode geometric inference, just with the right
    candidates excluded/biased), cursor-stability handling beyond the identity-keyed
    pooling prerequisite, a selling *action* on the Junk slot (it
    displays and totals, doesn't sell — Leatrix_Plus already does that part),
    library/framework dependencies of any kind (Ace3 etc. — distinct from the
    Junk.lua-style soft addon integration above, see DESIGN.md), and auto-pinning
    for the five named currencies other than Artisan's Moxie (Shard of Dundun's,
    Restored Coffer Keys, Coffer Key Shards, Remnants of Anguish, Field Accolades —
    no verified currency/item IDs, the user pins these via Blizzard's own UI
    instead — see `Currency.lua` above). Equipment items are never merged into a
    stack even when the itemID matches. Clicking a merged stack always acts on its
    first underlying slot (documented simplification, not a nav/cursor claim).
    Soulbound/warbound equipment is sorted by real reward-track name
    (Explorer/Adventurer/Veteran/Champion/Hero/Myth, via `C_TooltipInfo.GetBagItem`'s
    `ItemUpgradeLevel` tooltip line, cached per item-instance GUID — see
    `Categories.lua`), falling back to item quality only when no track line exists.
    An earlier pass used quality unconditionally, assuming track names were
    season-throwaway labels — the user corrected that (they're real, persistent item
    properties) and this was fixed same-session, untested against a live tooltip.
- **Target**: see `DESIGN.md` § Target architecture. Nav graph (tasks 1/2) and real
  update-granularity tuning (task 3) build on top of this once their investigation
  tasks have recorded decisions.
- Anything not listed under Current does not exist yet. Do not describe it as working.

## Boundaries

- WoW client Lua API (game/item/container state) — foreign data, validate at the
  boundary per `~/.claude/CLAUDE.md`.
- SavedVariables (config, junk overrides) — read back across a session boundary,
  validate before use.
- `references/` is read-only input, never a source to copy from — see
  `references/README.md`.

## Resume

- **Last state**: addon is live and symlinked into the real client
  (`Interface/AddOns/SpeedyBags` → this repo's `SpeedyBags/`, same-machine dev
  workflow, no sync step). This pass (2026-08-17) added three things the user asked
  for in one request: ConsolePort nav markers, a currency row, and a bank UI —
  `UI.lua` was refactored from a single hardcoded frame into a `NewBagView(opts)`
  factory so the bag view and bank view share one rendering implementation rather
  than becoming two copy-pasted files; `Data.lua`'s `Scan`/`Model` were generalized
  the same way (`Scan(bagIDs)` param, `ns.NewModel(getBagIDs)` factory) to back
  both. New files: `Currency.lua` (gold + Blizzard's native "Show in Backpack"
  currency list — no hardcoded currency IDs, see its own header comment for why),
  `Bank.lua` (`ns.GetBankBagIDs()` off `C_Bank.FetchPurchasedBankTabIDs`, warband
  bank listed first per the user's "default to warband bank" follow-up). ConsolePort
  markers: `nodeignore` on each view's main frame, `nodepriority = 1` on item slots
  (`UI.lua`'s `AcquireSlot`) — confirmed via research this session that category-
  header/subcategory-label `FontString`s need no tagging at all, since
  `ConsolePortNode` only scans mouse-enabled `Frame`s to begin with. `.toc` bumped
  to `0.5.0-mvp-bank-currency`, loads `Categories.lua`, `Junk.lua`, `Pawn.lua`,
  `Currency.lua`, `Data.lua`, `Bank.lua`, `UI.lua`, `SpeedyBags.lua` in that order
  (`Currency.lua`/`Bank.lua` both need to exist before `UI.lua` builds its two
  views; `Bank.lua` needs `Data.lua`'s `ns.NewModel` to exist first).
  `luacheck SpeedyBags/` run clean of syntax errors (only pre-existing "undefined
  global" noise from WoW API globals with no `.luacheckrc` declaring them — a
  gap that predates this session, not introduced by it).
  **Same-session follow-up round**, after the user's first in-game look: fixed a
  real bug (currency icons rendering as empty spots — `CreateTextureMarkup` called
  with a `0, 0` render size instead of `12, 12`, see `UI.lua`), moved the currency
  row from under the title to the bottom of the frame per feedback, added
  collapsible section headers (`AcquireHeaderButton`, `SpeedyBagsDB.collapsedSections`),
  added Artisan's Moxie profession auto-pinning (`Currency.lua`'s
  `AutoPinProfessionMoxie` — user supplied two real currency IDs directly, the rest
  were looked up via Wowhead to complete the verified pattern, see its own header
  comment), and added `Bank.lua`'s `HideDefaultBank` (reparents `BankFrame` onto a
  hidden frame at load, matching Baganator's own real production code — see
  DESIGN.md's corrected taint note) so SpeedyBags' bank view is the only one shown,
  per the user's explicit "explore how Baganator does it" direction. **Still none of
  this has been tested in-game past that first look** — the follow-up round is
  unverified.
- **Follow-up round (2026-08-17, same session)**: after the user tried the bank
  view in-game, it visibly overflowed the screen (five full-width subcategory
  blocks spilling past the frame edge — see the screenshot in this session's
  transcript). Four related fixes, all user-driven mid-implementation:
  1. **Scrolling**: `UI.lua`'s `NewBagView` now wraps everything below the title
     in a real `ScrollFrame` (`UIPanelScrollFrameTemplate`) over a `content`
     child frame; the outer frame clamps at `MAX_VIEW_HEIGHT` (640) instead of
     growing without bound, `scrollBarHideable` hides the slider when nothing
     needs scrolling.
  2. **Currency row pulled back out of the scroll**, per the user's own
     correction mid-implementation ("it's more of a part of the frame than an
     actual element") — parented to the outer `frame`, anchored fixed to its
     bottom, with the scrollFrame's own bottom anchor pulled up to leave it room.
  3. **Dynamic subcategory columns**: `SubcatCols(entries)` caps a block's
     column count at `min(SUBCAT_COLS, #entries)` instead of always the max —
     `RenderSubcategory`/`RenderSection` compute and wrap on each block's own
     width now, not a single `SUBCAT_WIDTH` constant.
  4. **Count-based subcategory ordering**: `OrderedSubcats` replaced
     alphabetical sorting with entry-count descending (ties broken
     alphabetically), per the user's "reasonable ordering / category
     compressing" request — also packs better now that blocks are dynamically
     sized.
  Alongside that, two feature adds the user asked for directly:
  5. **Quest item badge/hide**: `Data.lua`'s `Scan` pulls an inactive quest item
     (`isQuestItem` true, `isActive` false) into an aggregate badge sharing the
     Empty/Junk row, same shape as Junk; an active one stays a normal entry and
     gets Blizzard's own native quest-bang overlay (`btn:UpdateQuestItem`, no
     new texture, no addon dependency — pure native API). Explicitly scoped
     down from an earlier brainstorm that also covered soft integrations with
     ProfessionShoppingList and HousingItemTracker — the user vetoed both
     (PSL "is sufficient by itself"; HousingItemTracker "already implemented...
     let's not touch it") before any code was written for either.
  6. **Recent items row**: `Data.lua`'s `NewRecentTracker` gives each model its
     own session-only "recently seen" notion (diffs each model's own scan
     history — can't reuse `C_NewItems.IsNewItem`, since `ClearNewItemGlow`
     already erases that flag every render). A real bug was caught and fixed
     before it shipped, not after: the very first scan has no `previousCounts`
     baseline, so without an explicit `hasScannedBefore` guard it would have
     flagged the entire bag as Recent on addon load. Renders as real,
     individually-clickable item slots sharing the aggregate row, reusing a new
     `ConfigureItemSlot` helper factored out of `RenderSubcategory` for exactly
     this (also fixes a stale doc comment: `ClearNewItemGlow`'s header used to
     say "Recent items isn't a real tracked feature yet," now explains why it
     can't be Recent's data source instead).
  **None of this follow-up round has been tested in-game yet** — same caveat as
  the round before it, now compounding: nothing from either round has had a real
  client verification pass.
- **Third round (2026-08-17, same session)**: while reviewing the bank-overflow
  screenshot from the round above, the user flagged that Empty count silently
  combined Warband Bank space (shared across the account) with Personal Bank
  space (character-only), plus four more asks in the same message. All five:
  1. **Personal/Warband split into two real models** — `Bank.lua`'s single
     `ns.BankModel` (merged scan) is gone, replaced by `ns.PersonalBankModel`/
     `ns.WarbandBankModel`, both plain `ns.NewModel(getBagIDs)` instances —
     Data.lua's generic `Scan`/`NewModel` needed no changes at all.
  2. **`UI.lua`'s `NewBagView` generalized to render multiple groups**
     (`opts.groups`), each with its own complete section/subcategory breakdown
     and optional super-header — the bank view now visibly keeps "Warband
     Bank" and "Personal Bank" apart, matching Blizzard's own tab distinction,
     instead of one merged item list. Every pooled widget key gained a
     `groupKey` namespace prefix for this (headers, subcategory blocks,
     aggregate row widgets) — the bag view's single, unlabeled group produces
     identical keys to before (empty-string prefix), so this was a pure
     generalization, not a behavior change there.
  3. **Right-click category/subcategory transfer** (new `Transfer.lua`,
     `ns.TransferEntries`) — verified the underlying mechanism
     (`C_Container.PickupContainerItem` pickup-then-place pairs) against
     Baganator's own real, shipped `Transfers/FromBagsToBags.lua` before
     writing it, since this is the one piece that actually moves items and
     getting a protected-function call wrong could have broken click-to-use
     for the whole addon — turned out not to be a concern, `PickupContainerItem`
     was already established as non-protected in this project's own DESIGN.md.
     Section headers now register both mouse buttons (left = collapse toggle,
     unchanged; right = transfer the whole section); subcategory labels
     switched from a bare `FontString` to a real `Button`
     (`AcquireSubcatLabelButton`) since a FontString can't receive clicks at
     all. Direction is always "the other view" — bag view groups target
     `ns.GetWarbandBankBagIDs` (only actually works while at a banker, a real
     Blizzard restriction), both bank groups target `ns.BAG_IDS`.
  4. **"Deposit Reagents" button restored** (`Bank.lua`'s `ns.DepositReagents`,
     `C_Bank.AutoDepositItemsIntoBank` against both bank types) as a real
     button in the bank view's chrome, bottom-left — lost when `HideDefaultBank`
     suppressed Blizzard's own bank frame in an earlier round, per the user's
     own reasoning ("the transfer all reagents button should be preserved in
     the chrome somewhere").
  5. **Bank currency row scoped to `warbandGoldOnly`** — per the user's own
     reasoning that a bank can't hold currency it doesn't actually store, the
     bank view's currency row (`opts.currencyMode`) dropped `Currency.lua`'s
     full pinned-currency list entirely and shows only Warband Bank's own
     deposited-gold balance (`Bank.lua`'s `ns.GetWarbandBankGold`,
     `C_Bank.FetchDepositedMoney` — a real, separate pool from the player's
     own `GetMoney()`). A new `ACCOUNT_MONEY` event (`SpeedyBags.lua`) refreshes
     it, since `PLAYER_MONEY` only covers character gold.
  **Also untested in-game** — same compounding caveat as the round before it,
  now three rounds deep with zero live verification. This round in particular
  carries the most real risk of the whole pass: it's the first one that
  actually *moves items* (Transfer.lua) rather than just displaying them
  differently, so a mistake here has real gameplay consequences, not just a
  cosmetic bug.
- **Fourth round (2026-08-17, same session)**: user's first real in-game
  screenshot of the third round's bank view. Two things confirmed working
  from the screenshot itself (not guessed): the `"Warband: <gold>"` currency
  row and the Deposit Reagents button both rendered, meaning the third
  round's code really did load. Two things it prompted:
  1. **Masonry layout** replaced row-then-wrap entirely (`UI.lua`'s
     `RenderSection`) — the user's own diagram showed a full row of small
     Crafting subcategories that would have fit in the leftover space below
     a shorter column from the row above, instead of being forced onto an
     entirely new row. `SECTION_COLUMNS` (5) fixed-position column slots,
     each with its own running height; every block goes into whichever
     column is currently shortest. Deliberately did NOT also build the
     user's follow-on idea (precompute Warband's layout once globally, each
     character's once per-character, reflow only on window close) in this
     same pass -- see the round below for why that idea was right and got
     built shortly after, not why it was skipped.
  2. **Deposit Reagents tooltip** — the user asked which bank the button
     targets; the honest answer is genuinely both (whichever bank type has
     a reagent-flagged tab picks the items up), so a tooltip now says that
     outright rather than picking one to imply. Superseded almost
     immediately (see the round below) once the user clarified they want a
     specific, chosen bank, not "whichever one happens to have the flag."
  Whether the Personal Bank section is actually missing from that
  screenshot or just below the visible/scrolled area (the window looked
  tall enough to plausibly be hitting `MAX_VIEW_HEIGHT`'s scroll cutoff)
  was NOT independently confirmed — flagged as a guess, not fixed as a bug,
  since there was no direct evidence either way. This "Personal Bank
  missing" open question got resolved by construction in the round below,
  not investigated directly.
- **Fifth round (2026-08-17, same session)**: two corrections from the user,
  both catching a mistake in this session's own reasoning rather than
  reporting a new bug.
  1. **Real tabs, not stacked groups** — the user: "which bank does the
     'deposit reagents' button deposit them to?" plus "this is why i wanted
     personal bank and warband bank as separate tabs" (repeating a point
     from the round before, meaning the stacked-groups design still hadn't
     landed what they'd actually asked for). `UI.lua`'s `NewBagView` now
     shows exactly one group at a time behind real switchable tab buttons
     -- `SelectedGroup()`/`SelectedGroupIndex()`, persisted per-view via
     `SpeedyBagsDB.selectedGroup`. Placed at the BOTTOM of the frame, above
     the currency/deposit row, per the user's own follow-up on placement
     ("tabs are traditionally below the frame ... could also utilize the
     currency and action buttons row" -- kept as its own row rather than
     merged into that one, since 2 tabs + a deposit button + a gold display
     all sharing one row got visually crowded). This also resolved question
     1 outright: `Bank.lua`'s `ns.DepositReagents` now takes a specific
     `bankType` and `UI.lua`'s button passes `SelectedGroup().bankType` --
     no more "tries both, whichever has the flag," since the user has a
     reagent-deposit tab configured on BOTH banks, making that genuinely
     ambiguous rather than just apparently so. Caught and fixed a real bug
     while wiring the tab buttons' `OnClick`: it initially referenced
     `view.Refresh()`, but `view` wasn't declared as a local until much
     later in the same function -- without a real local `Refresh` forward-
     declared earlier in the file (there already was one, for the section-
     header click handler; moved it up before the tab-button code and
     removed the now-duplicate later declaration), that click handler would
     have silently resolved to a global `view` at runtime instead of the
     view actually being built.
  2. **"Compute once, don't recompute on every open" is the addon's own
     founding purpose, not a nice-to-have** — this session's masonry-layout
     writeup had said "no evidence yet that live recompute... actually
     costs anything," which the user corrected sharply and correctly: (a)
     the addon exists specifically because other bag addons are slow to
     open, per `DESIGN.md`'s own Purpose section, so "prove it's slow
     first" was the wrong bar entirely; (b) more fundamentally, WoW's
     client is single-threaded, so synchronous Lua work sits directly in
     the render-thread path -- the question is never "is this slow in the
     abstract," it's "does this block a frame," which is exactly what
     `DESIGN.md` invariant 4 already says ("bulk operations never block the
     rest of the UI... implies an event/incremental update model"). Fixed
     the concrete, implementable half of this: `SpeedyBags.lua`'s
     `MakeScheduler` no longer gates model updates on the owning view's
     visibility, so scanning (container/quest/item info) now runs
     continuously in the background, spread across the many individual
     `BAG_UPDATE`-family events that already fire during normal play,
     exactly like `Currency.lua` already always has -- `view.Show()`
     dropped its forced `model.Update()` entirely and just calls
     `Refresh()`, since the data's already current by the time the window
     opens. The deeper half -- `Refresh()`'s own masonry/layout pass is
     still one synchronous call per render, not diffed or spread across
     frames -- is genuinely NOT fixed; it's `DESIGN.md`'s own already-
     stated target architecture ("Render layer: subscribes to data-layer
     diffs, patches only affected slots"), gated on the task-3 investigation
     this project has never actually done. Correcting the doc language that
     dismissed this was itself part of the fix, not just the code.
  **Also untested in-game**, same as every round today.
- **Sixth round (2026-08-17, separate session, responding to the first real
  in-game pass over the five rounds above)**: the user reported five live-
  testing findings (recorded in `TODO.md`'s "Live testing findings" section);
  three addressed this round, two left genuinely open rather than guess-fixed:
  1. **`Transfer.lua` rebuilt as a step-driven queue** — the user's report
     ("only the first item actually moves") matched this project's own prior
     diagnosis in `TODO.md`: `PickupContainerItem` doesn't complete
     synchronously enough to chain multiple pickup/place pairs in one Lua
     call the way the original single synchronous loop assumed. Rebuilt on
     Baganator's own real shape (confirmed against
     `Transfers/FromBagsToBags.lua` again) — `BuildQueue`/`StepQueue`, one
     pickup/place pair per step, each waiting a full frame
     (`C_Timer.After(0, ...)`) before the next, re-checking the source slot
     at step time since an earlier step can shift bag contents.
  2. **Ghost items after transfer fixed as the same root cause** — added
     `RescanAllModels()`, called once the step queue drains (or hits combat
     lockdown / no space), refreshing all three models
     (`ns.Model`/`ns.PersonalBankModel`/`ns.WarbandBankModel`)
     unconditionally rather than tracking exactly which two were involved —
     simpler, and `model.Update()` is a cheap no-op re-scan on an unaffected
     model.
  3. **Masonry recompute cost partially mitigated, not solved** — `UI.lua`'s
     `NewBagView` now debounces `Refresh()` itself
     (`ScheduleRefresh`/`C_Timer.NewTimer(0.1, ...)`, cancel-and-reschedule
     on every model change) so a burst of updates spread across several
     frames collapses into one trailing render. Deliberately did NOT build
     the deeper diff-based "patch only affected slots" render — that's
     `DESIGN.md`'s own stated target architecture, gated on the still-open
     task 3 investigation, not something to improvise here.
  4. **Left open, not guess-fixed**: whether the "Personal Bank tries to
     move to Warband Bank" report was a distinct bug or a symptom of bug 1
     above — by inspection `transferTargetBagIDs` is correctly reassigned on
     every render including tab switches, no stale-closure path found, so
     this is most likely (not confirmed) the same root cause as bug 1. Also
     left open: bank→bag ghosting via plain drag-and-drop (never goes
     through `Transfer.lua` at all, a separate code path) — the relevant
     bank-slot-changed event routing looks correct by inspection, same as
     the transfer-ghosting bug looked correct by inspection before it turned
     out not to be, so this needs a live-client look, not an inference.
  `luacheck SpeedyBags/` clean (153 pre-existing WoW-global warnings, 0
  errors, 0 new). **None of this has been tested in-game yet either** —
  still zero live verification across all six rounds.
- **Next step**: get all six rounds in front of the user for a real in-game
  pass — this is now, by a wide margin, the single biggest untested surface
  in the project. Specific to the fifth round (supersedes the fourth/third
  rounds' "does it show two stacked banks" questions below -- that's not
  the design anymore): do the tab buttons actually switch between Warband
  Bank and Personal Bank; does the currently-selected tab actually gray
  out/disable as the "you're here" indicator; does clicking Deposit
  Reagents while a specific tab is selected actually deposit into ONLY
  that bank; does opening the bag/bank window now feel noticeably snappier
  than before (the actual, subjective thing the scan/render decoupling was
  for); does the Personal Bank tab's currency row correctly show character
  gold. Specific to the fourth round: does masonry actually pack
  small subcategories into gaps left by taller columns instead of forcing a
  new row; does the Deposit Reagents tooltip read correctly on hover
  (superseded -- it now says which bank, not "checks both", so re-check the
  new wording specifically). Specific to the
  third round: does right-click on a section
  header actually transfer its items (bag→warband bank, either bank→bags);
  does right-click on a subcategory label do the same for just that block;
  does the "no space to transfer" message actually appear via `UIErrorsFrame`
  when the target is full instead of silently failing or erroring; does the
  bank view actually show "Warband Bank" and "Personal Bank" as two visually
  separate blocks now instead of one merged list; does the Deposit Reagents
  button actually deposit anything (and does it only need one bank type, or
  really both, depending on where the user's reagent-flagged tab lives); does
  the bank's currency row actually show Warband gold correctly and nothing
  else. Then, still carried over from the rounds before this one: does the
  bank view actually scroll (mouse wheel + slider) instead of
  overflowing; does the currency row actually stay put at the bottom while the
  content above it scrolls; do Parts/Optional-Reagents-style small subcategories
  actually render narrower now, and does the row-packing look sane; does an
  inactive quest item actually get badged/collapsed and an active one actually
  show the native quest-bang overlay; does the Recent row actually populate on
  loot and self-expire after 5 minutes without spamming update churn; do currency
  icons actually render, does the currency row read fine at the bottom now that
  it's fixed frame chrome, do section headers actually collapse/expand and stay
  collapsed, does Artisan's Moxie actually auto-pin, does the bank view appear
  alone (Blizzard's default suppressed) without taint symptoms. Also still
  unconfirmed from the earlier round: does `C_Bank.FetchPurchasedBankTabIDs`/
  `Enum.BankType`/`Enum.BagIndex.AccountBankTab_*`/`CharacterBankTab_*` actually
  match this session's research (an Explore-agent pass over
  `references/wow-ui-source` and `references/Baganator`, not hands-on
  verification) — bank tab IDs specifically were the least-verified part of that
  pass. After all of that: task 1/2's hand-authored nav-graph module (`DESIGN.md`
  invariant 5's `Cursor:Navigate` patch) is still the next real architectural
  step — nothing this session touched that.
- **Hazards**: flake package list is still unverified against actual nixpkgs
  attribute names — `nix flake show`/`nix flake check` fail in the Claude Code
  sandbox environment itself (pre-existing `NIX_STORE` issue unrelated to this
  project), needs `direnv exec .` on the real system to verify. `UI.lua`'s
  subcategory blocks are still not measured against label text via
  `GetStringWidth` (their width is now dynamic by entry count, but a long label
  on a narrow block can still visually overflow it) — cosmetic, not a
  correctness bug. The currency-row widgets have the same fixed-width tradeoff
  (100px gold, 80px per currency) and are equally unverified against real
  currency-name/quantity widths. Reward-track name extraction (`Categories.lua`'s
  `GetUpgradeTrackName`) assumes a tooltip line format ("Champion 4/8") that
  couldn't be verified against a real live tooltip — first thing to check if
  Equipment subcategories look wrong. `MAX_VIEW_HEIGHT` (640) is a plain
  constant, not derived from the user's actual screen/UI-scale — untested
  whether it's a sane cap on their actual setup, just a reasonable guess.
  `UIPanelScrollFrameTemplate` is Blizzard's own soft-deprecated-in-favor-of-
  ScrollBox widget — still shipped in 12.1.0, no removal signal, but worth
  knowing if a future client patch ever breaks it. `RECENT_WINDOW_SECONDS` (300)
  and `RECENT_ICON_CAP` (6) are both unverified guesses at reasonable values —
  first things to tune if Recent feels too noisy or too sparse in practice.
  Two default-position frames (`RIGHT`/`LEFT` of screen center) are untested for
  overlap/clamping on smaller resolutions. `Transfer.lua`'s `ns.TransferEntries`
  re-scans the target bag list for the next empty slot after every single
  item move rather than pre-computing a list -- correct as long as container
  state is immediately consistent client-side after a pickup/place pair
  (true for this kind of single local pass, per Baganator's own simpler code
  paths), but genuinely untested for a large transfer (a full Materials
  section, say) against a live client. `ns.DepositReagents` tries both bank
  types unconditionally rather than knowing which one actually holds the
  reagent-flagged tab -- harmless if wrong (each call no-ops on a bank type
  that doesn't support auto-deposit) but unverified which tab(s) actually
  end up flagged for it on the user's own account. The "Warband: " prefix on
  the bank view's currency-row gold widget is a `+70px` width guess
  (`GOLD_WIDGET_WIDTH + 70`), unverified against how wide that text actually
  renders.
