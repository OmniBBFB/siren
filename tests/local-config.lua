local api = vim.api
local plugin = require("lazy.core.config").plugins["siren"]
assert(plugin and plugin._.loaded, "Git-managed lazy.nvim plugin did not load")
assert(plugin[1] == "OmniBBFB/siren", "Expected Git repository spec")
assert(plugin.dir == vim.fn.stdpath("data") .. "/lazy/siren", "Expected lazy-managed checkout")
assert(require("siren").root == plugin.dir, "Runtime still depends on development checkout")
assert(vim.fn.isdirectory(plugin.dir .. "/node_modules/pele") == 1, "Renderer build did not install Pele")
assert(vim.fn.exists(":Siren") == 2, "Missing command")
assert(vim.fn.maparg("<Space>ma", "n") ~= "", "Missing local keymap")
local buf = api.nvim_get_current_buf()
local got, matches = false, {}
Snacks.image.doc.find(buf, function(found) matches = found; got = true end)
assert(vim.wait(10000, function() return got end, 20))
for _, m in ipairs(matches) do assert(m.ext ~= "chart.mmd", "Snacks still owns Mermaid") end
api.nvim_buf_set_lines(buf, -1, -1, false, { "", "![normal](/home/csc/outputs/snacks-image-test/test.png)" })
got = false
Snacks.image.doc.find(buf, function(found) matches = found; got = true end)
assert(vim.wait(10000, function() return got end, 20))
assert(#matches == 1 and matches[1].src:find("test.png", 1, true), "Ordinary Snacks images lost")
local kitty = require("siren.kitty")
kitty._write = function() end
vim.cmd("Siren all")
assert(vim.wait(20000, function()
  local s = require("siren").status()
  return not s.busy and s.results and #s.results == 2
end, 20), "Git checkout failed to render real diagrams")
local out = { passed = true, lazy_loaded = true, command = true, keymap = true,
  git_url = plugin.url, installed_dir = plugin.dir, renderer_build = true, real_render = true,
  snacks_mermaid_disabled = true, ordinary_images_preserved = true }
vim.fn.writefile({ vim.json.encode(out) }, "/home/csc/app/siren/.test-output/local-config.json")
print("PASS Git-managed lazy.nvim install/build/render, Mermaid ownership, ordinary Snacks images")
vim.cmd("qa!")
