local api = vim.api
local plugin = require("lazy.core.config").plugins["siren.md"]
assert(plugin and plugin._.loaded, "Local lazy.nvim plugin did not load")
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
local out = { passed = true, lazy_loaded = true, command = true, keymap = true,
  snacks_mermaid_disabled = true, ordinary_images_preserved = true }
vim.fn.writefile({ vim.json.encode(out) }, "/home/csc/app/siren/.test-output/local-config.json")
print("PASS local lazy.nvim integration, Mermaid ownership, ordinary Snacks images")
vim.cmd("qa!")
