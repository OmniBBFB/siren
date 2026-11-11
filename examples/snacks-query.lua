-- Optional user configuration, not installed by the plugin.
-- Keep all existing image queries except Snacks' Mermaid fence pattern.
-- Run after Snacks is on runtimepath and before opening Markdown.
local parts = {}
for _, file in ipairs(vim.treesitter.query.get_files("markdown", "images")) do
  local text = table.concat(vim.fn.readfile(file), "\n") .. "\n"
  text = text:gsub("; extends", "")
  text = text:gsub("%(fenced_code_block.-%) @image%s*\n", function(pattern)
    return pattern:find('"mermaid"', 1, true) and "" or pattern
  end)
  parts[#parts + 1] = text
end
vim.treesitter.query.set("markdown", "images", table.concat(parts, "\n"))
