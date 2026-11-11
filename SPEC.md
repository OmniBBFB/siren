# siren.md specification

## Installation

Default lazy.nvim spec uses "OmniBBFB/siren", main="siren", ft="markdown" and build="npm ci --ignore-scripts". Lazy manages checkout and updates; runtime paths derive from the installed plugin, including plugin.dir for optional Snacks query integration. Local dir is an explicit development override.

## Contract

Lua API: setup(opts), render(scope), float(), clear(), disable(), status().
Commands: :Siren [current|all|selection|float|clear|disable|status].
Optional line range selects all intersecting complete Mermaid blocks.
Default: manual activation, inline placement, source preserved, debounce=300ms.
Default Markdown-only keymaps are owned by setup({keymaps=...}); false disables all or individual actions. Attach to existing and future Markdown buffers, and clean owned mappings on reconfiguration.
Selection/current scopes tracked by extmarks; subsequent edits update those blocks only. All scope discovers new blocks.
No Markdown parser dependency beyond optional bundled Markdown Tree-sitter. Pele owns Mermaid parsing.

## Detection and errors

Only closed fenced Mermaid blocks are rendered; the Markdown language tag is case-insensitive (mermaid/Mermaid/MERMAID). Scanner understands >=3 backticks or tildes, matching closing fence character/length, optional indentation <=3 spaces, and avoids fences inside other fenced blocks. Nested list/blockquote fences require Tree-sitter.
Tree-sitter locates fenced_code_block ranges; closing delimiter is checked independently.
Failed current lookup notifies. Explicit all scan with no diagrams notifies about the required mermaid language tag; automatic scans stay quiet. Errors are deduplicated; failed blocks lose their stale image/link.

## Async

Each buffer session has a revision and each job has a source snapshot. At most one active buffer batch. Completion rescans before any display. Changed sources cause a refresh after debounce; old callbacks cannot restore cleared/closed/reconfigured sessions.
Edits during rendering coalesce into a new batch. Editing unrelated text can reuse cached image.
Atomic cache writes and a per-key process lock serialize concurrent metadata updates; renderer never receives shell-interpolated source.

## Renderer and cache

Node process reads JSON stdin, produces JSON stdout. Pele -> fixed SVG -> resvg PNG.
Pin dependencies in npm lockfile. Explicit fontFamily/fontSize and configurable fixed CSS variables; responsive=false, autoDirection=false. External images disabled.
Hash includes source, font, palette, scale, version signature, and temporal reference for time-dependent diagrams.
PNG, SVG and JSON sidecars use identical content key. metadata contains schema, key, source hash, dimensions, renderer versions, and origins[] with Markdown paths/observed times.
Moving a document adds its new path on reopening. Previous paths are historical evidence, not a guarantee of rename detection.
Explicit :SirenPrune [days] removes only old global cache objects; active paths protected. Linked project assets are never automatically pruned.

## Display

Native: Kitty virtual placements + U+10EEEE placeholders in extmark virtual lines. Separate owned image IDs, delete only owned IDs. Source is never hidden. Keep a logical fence anchor but move the display anchor to a visible line when another plugin uses conceal_lines on the closing fence; recheck after cursor/mode updates. Size uses terminal cell dimensions. Shared buffer windows use smallest visible width to prevent clipping; floats have their own placement and fit.
Native float is a scratch buffer with actual blank rows and per-row placeholder extmarks, q/Esc closes. Resizes refit, source changes refresh an open float.
Snacks: require Snacks.image with doc.inline enabled. Generated link group immediately follows closing fence, uses relative .siren/<hash>.png and HTML ownership markers. Update in memory, normal :write persists it; no implicit save. This mode marks Markdown modified. Managed links survive :disable; :clear removes managed links in the active scope. No independent Kitty display in this mode.
Snacks float delegates to Snacks.image.hover at the managed link.
Changing a linked block invalidates/removes its link until new output succeeds. Removed blocks have their owned orphan links removed on next refresh.
Markdown rename inside Neovim regenerates relative assets/metadata. External directory moves preserve relative links; moving only .md requires reopening/rendering to repair.
Snacks Mermaid matching must be disabled; ordinary images remain enabled. Do not patch global plugin queries at runtime.

## Validation

Headless Lua tests: fences, TS/fallback parity, scopes, async edits, failures, managed-link lifecycle, metadata/rename, resize and owned cleanup.
Node tests: real Chinese flowchart and sequence rasterization, palette flattening, errors, cache reuse.
Real local Kitty: inline and float, scroll, window resize, split, clear; Snacks mode actual link display with no duplicate native placement.
