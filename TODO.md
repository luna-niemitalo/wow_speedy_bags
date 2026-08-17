# TODO — implementation plan

Ordered checklist. Items tagged `(task N)` still need their `TASKS.md` investigation
resolved first — don't build past them until that task has a recorded decision.

## Known gaps
- [x] ~~In-combat item use/pickup~~ — resolved: slot buttons inherit Blizzard's real
      `ContainerFrameItemButtonTemplate`, so clicks are untainted in and out of
      combat. See `DESIGN.md` § Protected functions (taint) for the full story
      (including a wrong first diagnosis, corrected against a real repro).

## Tooling
- [ ] Install `wowlua-ls` in VS Code, confirm real hover/autocomplete on a
      `C_Container` call (task 5's last unverified step)
- [ ] Verify `nix/flake.nix` actually builds (`direnv exec .`) on the real system —
      untested in the sandbox that scaffolded it

## Framework decision
- [ ] Resolve task 6 (Ace3/LibStub/CallbackHandler — yes/no per piece) before writing
      any addon code beyond the current stub

## Data layer
- [ ] Resolve task 3 (event coalescing model — what triggers a re-render, at what
      granularity)
- [x] ~~Resolve task 4 (junk classification rule; Junk-slot interaction model)~~ —
      resolved 2026-08-16: reads Leatrix_Plus's own `_G.LeaPlusDB` (quality ==
      Poor + sellable, minus its exclude list/Keeper Ta'hult/grey-gear settings),
      falling back to Blizzard's bare Poor-quality rule if Leatrix_Plus isn't
      loaded. See `Junk.lua` and `DESIGN.md`'s external-integration note. No
      interaction model yet — the Junk slot displays count + hover-tooltip sell
      value, doesn't sell anything itself (Leatrix_Plus already does that).
- [ ] Bag/bank/currency state model, decoupled from rendering
- [ ] Subscribe to `BAG_UPDATE`-family events; diff, don't rebuild
- [x] ~~Junk classification as a single boundary~~ — resolved: `ns.IsJunk` in
      `Junk.lua` is the one field → one check → one destination point; `Data.lua`'s
      `Scan()` calls it once per slot and never creates a normal entry for junk.

## Render layer
- [x] ~~Item slot widget, built on the real `ItemButtonTemplate`~~ — resolved via
      `ContainerFrameItemButtonTemplate` (see Known gaps above; same fix, same file).
- [x] ~~Category-header widget~~ — resolved 2026-08-16: `Categories.lua` classifies
      each entry into a section (Crafting/Equipment/Misc/Old Stuff) + subcategory
      (source-based for crafting reagents, quality-or-slot for equipment depending on
      bind status, expansion name for outdated items); `UI.lua` renders sectioned,
      flow-wrapped subcategory blocks. This reverses the original MVP's "no
      categories" scoping decision — the user's own Baganator layout turned out to be
      a real usability requirement, not optional polish. Section headers still need
      `nodeignore` tagging once ConsolePort nav integration lands (see below) — not
      done yet, this pass was display-only.
- [x] ~~Junk aggregate slot widget (count/space-consumed, not per-item)~~ —
      resolved 2026-08-16: shares a row with the Empty widget (`UI.lua`'s
      `RenderAggregateRow`), count + total sell-value tooltip, no individual junk
      slots rendered.
- [ ] "Recent items" tracking (`C_NewItems.IsNewItem`) — the reference layout's
      Empty row is actually a Recent+Empty row; only Empty is implemented so far
- [ ] Wire render layer to data-layer diffs — patch only changed slots, never a
      full-frame rebuild in the loot/vendor/mail/unbox hot path (invariant 4)
- [x] ~~Keep slot frame identity stable across content changes~~ — resolved: slot
      widgets are pooled by `entry.key` (stable item identity — itemID for merged
      stacks, item GUID for equipment), not list position, so a new item appearing
      earlier in bag/slot scan order can no longer silently reassign an existing
      widget to a different item. Real bug hit and fixed 2026-08-16 (combining
      reagents into a new item type shifted scan order). Prerequisite for invariant
      2, not the whole thing — ConsolePort's own reselection is still task 2.

## ConsolePort nav integration
- [ ] Nav graph module: `graph[node][direction] = target`, built alongside slot
      layout
- [ ] Monkey-patch `Cursor:Navigate` (`ConsolePort_Cursor/View/Cursor.lua`, via
      `db.Cursor`) — `pcall`/shape-check guarded — to consult the graph first, fall
      through to the original geometric scan per-direction when no edge exists
- [ ] Tag every non-item-slot frame (category headers, Junk slot if applicable) with
      `SetAttribute('nodeignore', true)` — mandatory regardless of graph, it's the
      fallback's correctness net
- [ ] Tag item slots with `nodepriority` for cursor-stability reselection bias
- [ ] Verify fallback path with ConsolePort's Navigate unpatched/absent: nav still
      resolves cleanly via geometry + the above tags alone

## Cursor stability
- [ ] Verify cursor stays on the acted-on slot/stack across loot, sell, mail, and
      container-opening flows (invariant 2)
- [ ] Confirm the Knowledge Point UI surface (bag slot vs. separate frame) before
      building its fix (task 2)

## Validation (in-game, manual)
- [ ] Up/down/left/right from any item slot never lands on a category header
      (invariant 1)
- [ ] Bulk loot/mail/vendor operations never block interaction with other frames
      (invariant 4)
- [ ] Junk slot count matches actual aggregated junk, no per-item junk slots leak
      through
- [ ] `luacheck` clean
