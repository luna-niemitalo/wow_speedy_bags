#!/usr/bin/env nu
# Pulls the addon-development-relevant subset of warcraft.wiki.gg into
# references/warcraft-wiki/ as raw wikitext files, so API/event/widget docs
# are available locally without a web search. Re-run any time to refresh
# after a WoW patch or wiki edits -- it's a full re-pull each time, not
# incremental (the scope below is small enough that this doesn't matter).
#
# Scope is deliberately NOT the whole wiki: that's ~690k pages, almost all
# lore/quest/NPC/zone content irrelevant to addon dev. See DESIGN.md and
# the 2026-08-16 scoping decision in TASKS.md/chat history for why.
#
# Output is raw wikitext (MediaWiki template markup, not rendered prose) --
# that's the actual page *source*, consistent with how everything else in
# references/ is source rather than a rendered build.

let categories = [
    "API functions"
    "API events"
    "Widget methods"
    "Widget script handlers"
    "Widgets"
    "AddOns"
]

let api_base = "https://warcraft.wiki.gg/api.php"
let user_agent = "SpeedyBags-dev-mirror/1.0 (personal WoW addon dev reference; not for redistribution)"
let out_dir = "references/warcraft-wiki"

mkdir $out_dir

def fetch [params: record] {
    let query = ($params | url build-query)
    http get --headers [User-Agent $user_agent] $"($api_base)?($query)"
}

# Every page title in one category, following MediaWiki's cmcontinue
# pagination until exhausted.
def collect_titles [category: string] {
    mut titles = []
    mut cont = null
    loop {
        mut params = {
            action: "query"
            list: "categorymembers"
            cmtitle: $"Category:($category)"
            cmlimit: 500
            format: "json"
        }
        if $cont != null {
            $params = ($params | insert cmcontinue $cont)
        }
        let resp = (fetch $params)
        $titles = ($titles | append ($resp.query.categorymembers | get title))
        let has_more = ($resp | get -o continue) != null
        if not $has_more {
            break
        }
        $cont = $resp.continue.cmcontinue
        sleep 200ms
    }
    $titles
}

def sanitize [title: string] {
    $title | str replace --all "/" "_" | str replace --all ":" "_" | str replace --all "*" "_"
}

print "Collecting page titles..."
mut all_titles = []
for cat in $categories {
    let titles = (collect_titles $cat)
    print $"  ($cat): ($titles | length) pages"
    $all_titles = ($all_titles | append $titles)
}
$all_titles = ($all_titles | uniq)
print $"Total unique pages: ($all_titles | length)"

print "Fetching wikitext..."
let batches = ($all_titles | chunks 50)
mut done = 0
mut written = 0
for batch in $batches {
    let titles_param = ($batch | str join "|")
    let resp = (fetch {
        action: "query"
        prop: "revisions"
        rvprop: "content"
        rvslots: "main"
        titles: $titles_param
        redirects: 1
        format: "json"
        formatversion: 2
    })
    for page in $resp.query.pages {
        if ($page | get -o missing) == null and ($page | get -o revisions) != null {
            let content = (($page.revisions | first).slots.main.content)
            let fname = $"($out_dir)/(sanitize $page.title).wiki"
            $content | save -f $fname
            $written = $written + 1
        }
    }
    $done = $done + ($batch | length)
    print $"  ($done)/($all_titles | length) requested, ($written) written"
    sleep 300ms
}

print $"Done. ($written) pages written to ($out_dir)."
