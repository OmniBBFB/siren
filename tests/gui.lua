local root = "/home/csc/app/siren"
local api = vim.api
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/lazy/nvim-treesitter"))
vim.o.termguicolors = true
vim.o.swapfile = false
vim.o.number = true
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.foldenable = false
local mode = vim.env.SIREN_TEST_MODE or "native"
local errors = {}
vim.notify = function(msg, level)
  if level == vim.log.levels.ERROR then errors[#errors + 1] = msg end
end
if mode == "snacks" then
  vim.opt.runtimepath:prepend(vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim"))
  require("snacks").setup({ image = { enabled = true, doc = { inline = true, max_width = 90, max_height = 24 } } })
  -- Test fixture explicitly removes Snacks' own Mermaid renderer.
  vim.treesitter.query.set("markdown", "images", "")
end
require("siren").setup({ snacks_preview = mode == "snacks", debounce_ms = 100 })
vim.cmd.edit(root .. (mode == "snacks" and "/.test-output/snacks-demo.md" or "/examples/demo.md"))
vim.bo.filetype = "markdown"
local result = { mode = mode, passed = false, checks = {} }
local function save()
  result.errors = errors
  vim.fn.writefile({ vim.json.encode(result) }, root .. "/.test-output/gui-" .. mode .. ".json")
end
vim.schedule(function()
  local ok, err = xpcall(function()
    local rm = require("siren")
    rm.render("all")
    assert(vim.wait(20000, function()
      local status = rm.status()
      return not status.busy and #status.results == 2
    end, 50), "Render results missing")
    local source_buf = api.nvim_get_current_buf()
    result.source_buf = source_buf
    if mode == "snacks" then
      assert(vim.wait(15000, function()
        return #api.nvim_buf_get_extmarks(source_buf, Snacks.image.placement.ns, 0, -1, {}) > 0
      end, 50), "Snacks inline placement missing")
      assert(next(require("siren.kitty").placements) == nil, "Duplicate native placement")
      result.checks.inline = true
    else
      local kitty = require("siren.kitty")
      result.placements = {}
      for _, p in pairs(kitty.placements) do
        result.placements[#result.placements + 1] = { id = p.id, rows = p.rows, cols = p.cols }
      end
      assert(#result.placements == 2, "Native inline placement count")
      result.checks.inline = true
      vim.cmd.vsplit()
      vim.cmd("vertical resize 45")
      kitty.resize()
      for _, p in pairs(kitty.placements) do assert(p.cols <= 44, "Split width not applied") end
      result.checks.split_resize = true
      vim.cmd.close()
      kitty.resize()
      vim.cmd("normal! G")
      vim.cmd("normal! gg")
      result.checks.scroll = true
    end
    result.passed = true
    save()
  end, debug.traceback)
  if not ok then result.error = err; save() end
end)
