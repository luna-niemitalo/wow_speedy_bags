# References

Read-only reference material. **Never copy code from here into `SpeedyBags/`** — these
are examples of the problem done *badly* (per project goals in `../DESIGN.md`), not a
starting point. Everything in this directory is gitignored; it exists on disk for
`grep`/`Explore` but is not part of this project's history.

## Not a competitor: complementary QoL addons

`SpeedyBags` works *with* these, per the "external addon integration" distinction in
`DESIGN.md` — unlike the bag addons below, these aren't the problem being solved, so
soft-integrating with them (reading their SavedVariables, `## OptionalDeps:` in the
`.toc`) is fine, not a "no external dependencies" violation.

- `Plumber/` — `Peterodox/Plumber`, cloned 2026-08-16 while chasing down the source
  of the user's own quality-threshold-plus-exclusions junk-vendoring behavior.
  **Wrong guess** — checked its real source (`Modules/MerchantUI/`,
  `LootUI_Main.lua`, README): its only "junk" handling is cosmetic, merging
  Poor-quality items visually in the loot window popup, no bag-wide auto-sell logic
  at all. Kept cloned since it's still a real, well-regarded QoL addon that might be
  relevant later, but `Junk.lua` does not integrate with it.
- **Leatrix_Plus** — the actual source of the junk-vendoring behavior, confirmed via
  its real installed source (`Interface/AddOns/Leatrix_Plus/Leatrix_Plus.lua` on the
  live client — not cloned here, since `Junk.lua`'s integration reads its
  SavedVariables at runtime rather than studying its code as a one-off reference).
  See `Junk.lua`'s own comments for the exact mechanism and line references.

## Competitor addons (cloned, for behavioral study only)

- `AdiBags/` — category-based sorting, GPLv3. Good filter-rule reference.
- `Baganator/` — multi-flavor (retail + all classic versions) in one `.toc` set;
  worth studying its TOC/version-matrix approach even if the addon itself isn't a nav
  reference.
- `BagBrother/`
- `Bagnon/` — classic multi-bag-as-one-view approach.
- `BetterBags/` — most actively structured of the set. Has its own `AGENTS.md` /
  `.context/` docs worth reading for methodology, not for its UI/nav decisions:
  - `.libraries/wow-ui-source` — Blizzard's actual UI source, used as ground truth for
    mocks/annotations instead of guessing API behavior. Directly relevant to the "can
    we get a real language server / API defs" investigation task.
  - `annotations.lua` — hand-written EmmyLua (`---@class`/`---@field`) annotations for
    Blizzard widget types. Confirms EmmyLua-style annotations are viable for `lua-ls`.
  - `.context/api.md` — points at `https://warcraft.wiki.gg/wiki/World_of_Warcraft_API`
    and `https://warcraft.wiki.gg/wiki/Widget_API` as the canonical non-widget/widget
    API references, and the Lua 5.1 manual for language semantics.
  - Lua target is 5.1 only, enforced in CI + `.luacheckrc` + tooling — same constraint
    applies to us since it's a WoW runtime fact, not a BetterBags choice.
- `ConsolePort/` — the controller/gamepad input addon itself. 234 MB, has its own
  `CLAUDE.md`. Primary reference for the nav-target / cursor-focus investigation
  tasks — study how it defines nav nodes and cursor movement, not how bag addons
  (mis)integrate with it. **The actual nav engine isn't in this clone** — see
  `ConsolePortNode/` below; ConsolePort pulls it in as a `.pkgmeta` external
  (`Libs/External/ConsolePortNode`, not a git submodule — `.gitmodules` is empty),
  so it had to be cloned separately.
- `ConsolePortNode/` — `seblindfors/ConsolePortNode`, GPL-2.0, single 855-line file.
  This *is* ConsolePort's gamepad-cursor nav engine (`LibStub('ConsolePortNode')`,
  used from `ConsolePort_Cursor/Controller/Nudge.lua`). **Confirmed (task 1,
  2026-08-16): pure geometric candidate search, no registerable adjacency graph** —
  `NavigateToBestCandidate`/`NavigateToClosestCandidate` scan all cached candidate
  nodes and pick the best by angle+distance from the current node's live on-screen
  center every time a direction is pressed. The real override surface is a
  documented frame-attribute contract instead: `nodeignore` (excludes a frame from
  candidate selection — the actual mechanism for keeping category headers out of the
  item-slot up/down/left/right path), `nodepriority` (tiebreak/reselect weight, also
  relevant to task 2's cursor-stability question via `NavigateToArbitraryCandidate`),
  `nodesingleton`, `nodepass`. Full findings and the `DESIGN.md` invariant-5 wording
  note this implies are in `TASKS.md` task 1.

## WoW API reference material (pulled 2026-08-16, task 5)

- `wow-ui-source/` — `Gethe/wow-ui-source`, shallow clone of the `live` branch.
  Ground-truth mirror of Blizzard's actual FrameXML/Lua UI source, incl.
  `Blizzard_APIDocumentationGenerated` (the machine-generated API doc source both
  annotation projects below build on). 34 MB. License not stated in the repo; treated
  as read-only reference, not something to redistribute.
- `vscode-wow-api/` — `Ketho/vscode-wow-api`, full clone. MIT. The `Annotations/`
  subtree is a ready-to-use LuaLS/EmmyLua (`---@class`/`---@field`) annotation set
  covering the WoW Lua 5.1 environment, widgets, events, CVars, and `Enum`/`Constants`
  — generated from `Blizzard_APIDocumentationGenerated` + warcraft.wiki.gg. Confirmed
  it has full `C_Container` coverage (`GetBagSlotFlag`, `GetBackpackSellJunkDisabled`,
  etc.) — directly relevant to task 3/4. Ships as a VS Code extension that
  self-activates on any folder with a `.toc` file (`ketho.wow-api` on the
  Marketplace) — no manual `.luarc.json` wiring needed if developing in VS Code.
- `wowlua-ls/` — `TradeSkillMaster/wowlua-ls`, shallow clone. GPL-3.0, in beta. A
  **purpose-built WoW language server** (not a LuaLS-plus-stubs setup): 9,000+ stubs
  built in, typed event payloads, XML frame/template awareness, `.toc` awareness,
  metatable/generics inference. Its `stubs/overrides/` explicitly says it replaces
  "Ketho's vendored LibSharedMedia-3.0 annotations" — i.e. it's built on top of the
  same Ketho/Blizzard-doc lineage, not an independent source. Distributed as a
  compiled binary + `stubs/precomputed.bin.zst` (not plain-text annotation files to
  grep), installable via VS Code Marketplace (`TradeSkillMaster.wowlua-ls`, binary
  bundled), JetBrains Marketplace, or a downloaded/`cargo build --release` binary for
  Neovim (relevant for `mobile_fox`). Stronger tooling than plain `lua-language-server`
  + Ketho annotations if it proves stable enough to depend on — decision recorded in
  `TASKS.md` task 5.

Not pulled: `SabineWren/wow-api-type-definitions` (targets WoW 1.12.1/vanilla, wrong
flavor for this project) and `awesome-wow` (a links list, not reference material
itself — worth a read but not a clone).

## `wow-client-source/` — extracted from the actual installed client (2026-08-16)

Not a clone — pulled directly out of this machine's real WoW client CASC storage
(`/media/luna/games/World of Warcraft/_retail_`, build `12.1.0.69299`) using
`~/dev/casc-tool` (Luna's own CASC CLI) against the `community-listfile.csv` in
`/media/luna/userdata/Downloads/`. This is the actual live-build source, not a
mirror that might lag a patch behind `wow-ui-source`. 121K.

- `interface/addons/blizzard_uipanels_game/mainline/ContainerFrame.lua` + `.xml` —
  the real bag-frame implementation (this build ships it merged into the
  `Blizzard_UIPanels_Game` mega-addon, not a standalone `Blizzard_ContainerFrame`
  folder like older client versions/older docs describe — don't search for the old
  path). **Finding**: `ToggleBag_Individual` (line ~189) calls
  `CanAutoSetGamePadCursorControl(true)` / `SetGamePadCursorControl(true)` when
  opening a bag frame that wasn't already open — confirms Blizzard has *some* native
  gamepad-cursor API distinct from ConsolePort's own implementation. Checked
  `vscode-wow-api`'s annotations for both: they exist only as bare wiki-stub
  declarations (no params/return documented) — a real lead for task 1/2, not a
  solved mechanism. Worth an in-game trace (does it explain any nav behavior beyond
  "focus lands somewhere sane on open") before assuming more than this.
- `interface/addons/blizzard_uipanels_game/mainline/BankFrame.lua` + `.xml` — same
  addon's bank-side equivalent.
- `interface/addons/blizzard_itembutton/{mainline,shared}/ItemButtonTemplate.lua` +
  `.xml` — the actual `ItemButton` widget class every bag slot is built from.
  `BetterBags/annotations.lua`'s hand-written `---@class ItemButton` (see above) is
  an outside guess at this same thing; this is the real source of truth. Diff them if
  the annotation ever seems wrong.
- No native gamepad *nav-graph* (adjacency/registration) system turned up in any of
  these files — searched for `*gamepadui*`, `*navigat*`, `*cursor*` broadly across
  the whole client tree first. Consistent with `DESIGN.md`'s assumption that nav
  order is positionally inferred rather than explicitly registered; ConsolePort
  remains the primary source for task 1, not Blizzard's own client.

To pull more files the same way: `casc-tool list '<mask>' --storage
"/media/luna/games/World of Warcraft/_retail_" --listfile
/media/luna/userdata/Downloads/community-listfile.csv`, then `extract` by exact
path. Windows-style backslash paths from the listfile need manual re-nesting into
real directories on extract — `casc-tool extract` writes the literal name as one
path component, and shell escape handling for backslashes is shell-dependent, so
build the output path explicitly per file rather than scripting a bulk rename.

## `warcraft-wiki/` — mirror of warcraft.wiki.gg's addon-dev categories (2026-08-16)

Not a clone or a full-site dump — the wiki is ~690k pages (342k articles, 201k
images, mostly lore/quests/NPCs/zones), a literal mirror is untenable and almost
entirely irrelevant here. Pulled via `scripts/fetch-warcraft-wiki.nu` (a real,
re-runnable tool, not a one-off — run it again any time to refresh after a patch or
wiki edit), scoped to exactly the categories addon dev actually needs:
`Category:API functions` (6,803 pages), `API events` (2,037), `Widget methods`
(1,256), `Widget script handlers` (44), `Widgets` (54), `AddOns` (33) — 10,226
unique pages total via the MediaWiki API (`api.php`, `list=categorymembers` +
`prop=revisions`, redirects followed). Each page is saved as raw **wikitext**
(MediaWiki template markup like `{{apisig|...}}`, not rendered prose) — that's the
actual page *source*, consistent with everything else in `references/` being source
rather than a rendered build; still fully greppable for parameter names, argument
docs, and notes without a web search. CC BY-SA 4.0 (per the wiki's own footer) —
treated as read-only reference like everything else here, not redistributed.

## Community framework sources

Not yet pulled — Ace3/LibStub/CallbackHandler-1.0 ship vendored inside the addons
above (see `BetterBags/libs/`, `AdiBags/install-deps.sh`); pull standalone copies only
if task 6's framework evaluation needs to read implementation details the vendored
copies don't make convenient.
