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
  upgrade-advisor integration, a bank view, a currency row, and ConsolePort nav
  markers in `SpeedyBags/` — eight files, each one job:
  - `Data.lua` — `Scan(bagIDs)` reads a given combined bag-ID list into display
    entries, merging same-itemID non-equipment slots into one visual stack (even
    where the real inventory wouldn't stack them) and counting empty slots. Each
    new entry is classified via `ns.Categorize` (Categories.lua) into a
    `section`/`subcategory`. `ns.NewModel(getBagIDs)` builds a model holding the
    current scanned state and an `OnChanged` listener list — the only thing that
    mutates state or triggers a rescan; `ns.Model` (bag view, static `ns.BAG_IDS` —
    Backpack + Bag_1-4 + ReagentBag) and `Bank.lua`'s `ns.BankModel` (bank view,
    dynamic bag-ID list) are both instances of it, one scanner shared by both views.
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
  - `Bank.lua` — `ns.GetBankBagIDs()` drives the bank view's bag-ID list off
    `C_Bank.FetchPurchasedBankTabIDs` for both `Enum.BankType.Account` (warband
    bank, listed first — user asked for the bank view to default to it) and
    `Enum.BankType.Character`, gated on actual tab-purchase state rather than
    scanning a fixed tab-ID range; never *reads* state back off the `BankFrame`/
    `BankPanel` globals — see DESIGN.md's bank-taint note. `HideDefaultBank`
    (called once at load) does structurally touch `BankFrame` — reparenting it
    onto a hidden frame and clearing its `OnHide`/`OnEvent`/`OnShow` scripts,
    matching Baganator's own real production code exactly — so SpeedyBags' bank
    view is the only one the player sees. No separate Reagent Bank handling
    needed: the modern client folded it into regular character-bank tabs.
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
  - `UI.lua` — `NewBagView(opts)` is a factory, not a single frame: it builds one
    independent view (its own frame, its own pooled widgets, bound to one model)
    from `opts.model`/`opts.name`/`opts.slotPrefix`/`opts.point`. `ns.BagView`
    (bag, `ns.Model`) and `ns.BankView` (bank, `ns.BankModel`) are both built from
    it — one rendering implementation for both windows, not two copy-pasted files,
    per the user's "bank UI as a reflection of this" ask. Sectioned, flow-wrapped
    rendering: collapsible section headers (`AcquireHeaderButton` — real `Button`s
    with a click handler toggling `SpeedyBagsDB.collapsedSections`, persisted and
    shared between both views), subcategory label+item blocks wrapping at the frame
    edge, an aggregate row (Empty count + Junk count/sell-value tooltip) positioned
    between Equipment and Misc (matching the reference layout's ConsolePort-nav-
    motivated placement), and a right-to-left currency row (gold + `Currency.lua`'s
    pinned currencies) at the **bottom** of the frame (moved there from an initial
    under-the-title placement per the user's in-game feedback), all pooled and
    keyed by `entry.key` (stable item identity — itemID for merged stacks, item
    GUID for equipment) so scan-order churn can't silently reassign a widget to a
    different item. Item slots inherit Blizzard's real
    `ContainerFrameItemButtonTemplate` so click-to-use/pickup run as untainted
    Blizzard code — confirmed working in-game (§ Resume). Equipment slots also show
    Pawn's `UpgradeIcon` (a native template region, no new texture) and item level
    (`C_Item.GetDetailedItemLevelInfo`, accounts for upgrades unlike the static base
    ilvl). New-item glow is explicitly suppressed (`ClearNewItemGlow`) since we
    never call Blizzard's own `UpdateNewItem` and it would otherwise default to
    shown on everything after a reload; the default button chrome (`NormalTexture`)
    is cleared too, keeping only the quality-colored `IconBorder` — both real bugs
    the user hit in-game, not anticipated. Each view's main content frame carries
    `nodeignore` (so its own drag-enabled backdrop isn't itself a ConsolePort nav
    candidate); item slots carry `nodepriority = 1` (reselection bias toward real
    items); collapsible section headers carry `nodeignore` too, since being
    clickable makes them a valid geometric nav candidate otherwise (unlike plain
    `FontString` labels) — all fallback-net tagging DESIGN.md invariant 5 requires
    regardless of whether the hand-authored nav-graph module exists yet (it
    doesn't — see TASKS.md task 1). Renders only from its bound model's
    already-scanned state; never scans bags itself.
  - `SpeedyBags.lua` — event wiring: `BAG_UPDATE`/bank-slot-changed events are each
    coalesced via `C_Timer.After(0, ...)` (one shared `MakeScheduler` factory, bag
    and bank each get their own debounced instance) into a single deferred
    `model.Update()` rather than scanning inline in the event handler (data-mutation
    and rendering are deliberately decoupled, per invariant 4's intent, though task
    3 itself is still open); the default bag toggle (`ToggleBackpack`/
    `ToggleAllBags`/etc.) is redefined to open the bag view. `BANKFRAME_OPENED`/
    `BANKFRAME_CLOSED` show/hide the bank view — the only one visible, since
    `Bank.lua`'s `HideDefaultBank` already suppressed Blizzard's own. `PLAYER_MONEY`/
    `CURRENCY_DISPLAY_UPDATE` drive `Currency.lua`. `ADDON_LOADED` also seeds
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
    pooling prerequisite, "Recent items" tracking (the reference layout's middle row
    is Recent+Empty; only Empty exists), a selling *action* on the Junk slot (it
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
- **Next step**: get this follow-up round in front of the user for another real
  in-game pass: do currency icons actually render now; does the currency row read
  better at the bottom; do section headers actually collapse/expand and stay
  collapsed across a reopen; does Artisan's Moxie actually auto-pin for a character
  with a trained profession; does the bank view now appear alone (Blizzard's default
  suppressed) without any taint symptoms (`UseContainerItem` still working on both
  bags and bank after visiting a banker). Also worth confirming in-game: does
  `C_Bank.FetchPurchasedBankTabIDs`/`Enum.BankType`/
  `Enum.BagIndex.AccountBankTab_*`/`CharacterBankTab_*` actually match what this
  session's research (an Explore-agent pass over `references/wow-ui-source` and
  `references/Baganator`, not hands-on client verification) reported — bank tab
  IDs specifically were the least-verified part of this pass. After that: task 1/2's
  hand-authored nav-graph module (`DESIGN.md` invariant 5's `Cursor:Navigate` patch)
  is still the next real architectural step — this pass only did the fallback-net
  tagging invariant 5 requires regardless, not the graph itself.
- **Hazards**: flake package list is still unverified against actual nixpkgs
  attribute names — `nix flake show`/`nix flake check` fail in the Claude Code
  sandbox environment itself (pre-existing `NIX_STORE` issue unrelated to this
  project), needs `direnv exec .` on the real system to verify. `UI.lua`'s
  subcategory blocks are fixed-width (not measured against label text via
  `GetStringWidth`), so a long subcategory label can visually overflow its block —
  cosmetic, not a correctness bug, but will look off until addressed; the new
  currency-row widgets have the same fixed-width tradeoff (90px gold, 70px per
  currency) and are equally unverified against real currency-name/quantity widths.
  Reward-track name extraction (`Categories.lua`'s `GetUpgradeTrackName`) assumes a
  tooltip line format ("Champion 4/8") that couldn't be verified against a real
  live tooltip — first thing to check if Equipment subcategories look wrong.
  `ClearNewItemGlow` now proactively clears Blizzard's own new-item flag every
  render — if "Recent items" tracking (still deferred, see TODO.md) gets built
  later, it needs its own "seen it" state and can't rely on that flag surviving to
  be checked. Bank view opens *alongside* Blizzard's own default bank frame, not
  replacing it — see TODO.md's Bank UI entry for why suppressing it was deferred
  (taint risk). Two default-position frames (`RIGHT`/`LEFT` of screen center) are
  untested for overlap/clamping on smaller resolutions.
