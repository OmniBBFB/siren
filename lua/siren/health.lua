local M = {}
function M.check()
  local h = vim.health
  h.start("siren.md")
  local config = require("siren").config
  if vim.fn.has("nvim-0.11") == 1 then h.ok("Neovim >= 0.11") else h.error("Neovim 0.11+ required") end
  if vim.fn.executable(config.node) == 1 then h.ok("Node executable: " .. config.node) else h.error("Install Node >=20") end
  local root = require("siren").root
  if vim.fn.isdirectory(root .. "/node_modules/pele") == 1 then h.ok("Renderer installed")
  else h.error("Run npm ci --ignore-scripts in " .. root) end
  if config.snacks_preview then
    if _G.Snacks and Snacks.image then h.ok("Snacks.image available") else h.error("Enable Snacks.image") end
    h.info("Snacks doc.inline must be enabled; disable Snacks Mermaid query.")
  elseif require("siren.kitty").supported() then h.ok("Local Kitty environment")
  else h.error("Run in local Kitty without tmux/SSH") end
  local ok = pcall(vim.treesitter.get_parser, 0, "markdown")
  if ok then h.ok("Markdown Tree-sitter available") else h.info("Using manual fence fallback") end
end
return M
