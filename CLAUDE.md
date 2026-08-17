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

- **Current**: a working, categorized bag UI with a real junk slot and Pawn
  upgrade-advisor integration in `SpeedyBags/` — six files, each one job:
  - `Data.lua` — `Scan()` reads all combined bags (Backpack + Bag_1-4 + ReagentBag)
    into display entries, merging same-itemID non-equipment slots into one visual
    stack (even where the real inventory wouldn't stack them) and counting empty
    slots. Each new entry is classified via `ns.Categorize` (Categories.lua) into a
    `section`/`subcategory`. `ns.Model` holds the current scanned state and an
    `OnChanged` listener list — it's the only thing that mutates state or triggers a
    rescan.
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
  - `UI.lua` — sectioned, flow-wrapped rendering: section headers, subcategory
    label+item blocks wrapping at the frame edge, an aggregate row (Empty count +
    Junk count/sell-value tooltip) positioned between Equipment and Misc (matching
    the reference layout's ConsolePort-nav-motivated placement), all pooled and
    keyed by `entry.key` (stable item identity — itemID for merged stacks, item GUID
    for equipment) so scan-order churn can't silently reassign a widget to a
    different item. Item slots inherit Blizzard's real
    `ContainerFrameItemButtonTemplate` so click-to-use/pickup run as untainted
    Blizzard code — confirmed working in-game (§ Resume). Equipment slots also show
    Pawn's `UpgradeIcon` (a native template region, no new texture) and item level
    (`C_Item.GetDetailedItemLevelInfo`, accounts for upgrades unlike the static base
    ilvl). New-item glow is explicitly suppressed (`ClearNewItemGlow`) since we
    never call Blizzard's own `UpdateNewItem` and it would otherwise default to
    shown on everything after a reload; the default button chrome
    (`NormalTexture`) is cleared too, keeping only the quality-colored `IconBorder`
    — both real bugs the user hit in-game, not anticipated. Renders only from
    `ns.Model`'s already-scanned state; never scans bags itself.
  - `SpeedyBags.lua` — event wiring: `BAG_UPDATE` is coalesced via `C_Timer.After(0,
    ...)` into a single deferred `ns.Model.Update()` rather than scanning inline in
    the event handler (data-mutation and rendering are deliberately decoupled, per
    invariant 4's intent, though task 3 itself is still open), and the default bag
    toggle (`ToggleBackpack`/`ToggleAllBags`/etc.) is redefined to open this UI.
  - Also present: `nix/flake.nix` dev shell, `scripts/fetch-warcraft-wiki.nu` (a real,
    re-runnable tool, not a one-off), project docs (`DESIGN.md`, `TASKS.md`,
    `TODO.md`), and `references/` (gitignored, see `references/README.md`).
  - **Deliberately not yet in place**: ConsolePort nav-graph integration (section
    headers aren't `nodeignore`-tagged yet — display-only so far), cursor-stability
    handling beyond the identity-keyed pooling prerequisite, "Recent items" tracking
    (the reference layout's middle row is Recent+Empty; only Empty exists), a
    selling *action* on the Junk slot (it displays and totals, doesn't sell —
    Leatrix_Plus already does that part), library/framework dependencies of any kind
    (Ace3 etc. — distinct from the Junk.lua-style soft addon integration above, see
    DESIGN.md). Equipment items are never merged into a stack even when the itemID
    matches. Clicking a merged stack always acts on its first underlying slot
    (documented simplification, not a nav/cursor claim).
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
  workflow, no sync step). Confirmed working in-game through several real
  iterations, including two real visual bugs the user found live and reported
  directly (not anticipated): a blue "new item" glow on every slot after
  reload/relog/character-switch (we never call Blizzard's own `UpdateNewItem`, so
  it defaults to shown; fixed by replicating Blizzard's own clear via
  `ClearNewItemGlow`) and a double border (Blizzard's default `NormalTexture` button
  chrome stacking visually with the quality-colored `IconBorder`; fixed by clearing
  `NormalTexture`, keeping only `IconBorder`). Also added in this pass: Pawn
  integration (`Pawn.lua`) for upgrade arrows + item level on equipment, using
  Pawn's own documented third-party-bag API — the Junk slot got its own visual
  pass too (persistent placeholder with a darkened `bags-junkcoin` badge when
  empty, real Plumber-style stacked/darkened item icons when occupied, capped at 4
  during collection itself per the user's own resource-conservation ask, not just
  at display time). `.toc` bumped to `0.4.0-mvp-pawn`, loads `Categories.lua`,
  `Junk.lua`, `Pawn.lua`, `Data.lua`, `UI.lua`, `SpeedyBags.lua` in that order,
  `## OptionalDeps: Leatrix_Plus, Pawn`. Session's earlier milestones (protected-
  function fix, identity-stable pooling, full categorization, reward-track
  detection, Junk slot, warcraft.wiki.gg mirror) are unchanged from before — see
  git log / prior session notes for that history, not repeated here.
- **Next step**: get this pass's fixes and the Pawn integration in front of the
  user for a real re-test (does the glow/border fix actually look right; do
  upgrade arrows and item level render correctly; does the Junk slot's stacked-icon
  visual actually look like a "pile of junk" as intended). After that: task 1/2's
  nav-graph module (`DESIGN.md` invariant 5's `Cursor:Navigate` patch) is the next
  real architectural step, including finally `nodeignore`-tagging the section-
  header/subcategory-label/aggregate-row widgets so they don't become directional-
  nav targets.
- **Hazards**: flake package list is still unverified against actual nixpkgs
  attribute names — `nix flake show`/`nix flake check` fail in the Claude Code
  sandbox environment itself (pre-existing `NIX_STORE` issue unrelated to this
  project), needs `direnv exec .` on the real system to verify. `UI.lua`'s
  subcategory blocks are fixed-width (not measured against label text via
  `GetStringWidth`), so a long subcategory label can visually overflow its block —
  cosmetic, not a correctness bug, but will look off until addressed. Reward-track
  name extraction (`Categories.lua`'s `GetUpgradeTrackName`) assumes a tooltip line
  format ("Champion 4/8") that couldn't be verified against a real live tooltip —
  first thing to check if Equipment subcategories look wrong. `ClearNewItemGlow`
  now proactively clears Blizzard's own new-item flag every render — if "Recent
  items" tracking (still deferred, see TODO.md) gets built later, it needs its own
  "seen it" state and can't rely on that flag surviving to be checked.
