local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/lazy/nvim-treesitter"))
vim.g.mapleader = " "
local api = vim.api
local siren = require("siren")
require("siren.kitty")._write = function() end
local messages = {}
vim.notify = function(msg, level) messages[#messages + 1] = { message = msg, level = level } end
local failed, count = 0, 0
local function test(name, fn)
  count = count + 1
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then failed = failed + 1; print("FAIL " .. name .. ": " .. err) else print("PASS " .. name) end
end
local function reset()
  siren.setup({ cache_dir = root .. "/.test-output/trigger-cache", debounce_ms = 20 })
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "markdown"
  return buf
end
test("explicit all on unlabeled fence reports no Mermaid blocks", function()
  local buf = reset()
  local original = vim.fn.readfile(root .. "/tests/fixtures/unlabeled.md")
  api.nvim_buf_set_lines(buf, 0, -1, false, original)
  messages = {}
  vim.cmd("Siren all")
  assert(#messages > 0, "Explicit all silently returns with zero matches")
  assert(messages[1].message:find("mermaid", 1, true), "Notification should explain required Mermaid label")
  assert(vim.deep_equal(original, api.nvim_buf_get_lines(buf, 0, -1, false)), "Source must stay unchanged")
end)
test("setup registers Markdown keymap independently of lazy spec", function()
  reset()
  local mapping = vim.fn.maparg("<Space>ma", "n", false, true)
  assert(mapping.callback, "Siren setup does not register all keymap")
  assert(mapping.buffer == 1, "Siren maps should be local to Markdown buffers")
end)
test("current Markdown already open when setup runs gets its maps", function()
  reset()
  siren.setup({ keymaps = { all = "<leader>sa" } })
  assert(vim.fn.maparg("<Space>sa", "n") ~= "", "Setup ignored existing Markdown buffer")
  assert(vim.fn.maparg("<Space>ma", "n") == "", "Reconfiguration left stale mapping")
  siren.setup({ keymaps = false })
  assert(vim.fn.maparg("<Space>sa", "n") == "", "Disabling keymaps left stale mapping")
end)
test("map callback triggers real render on a labeled block", function()
  local buf = reset()
  local lines = vim.fn.readfile(root .. "/tests/fixtures/unlabeled.md")
  lines[1] = string.rep(string.char(96), 3) .. "Mermaid"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_win_set_cursor(0, { 1, 0 })
  local map = vim.fn.maparg("<Space>ma", "n", false, true)
  assert(map.callback, "Missing plugin-owned keymap")
  map.callback()
  assert(vim.wait(15000, function()
    local s = siren.status()
    return not s.busy and s.results and #s.results == 1
  end, 20), vim.inspect(messages))
  assert(#api.nvim_buf_get_extmarks(buf, require("siren.kitty").ns, 0, -1, {}) > 0, "Missing actual image placement")
  siren.clear()
end)
for _, method in ipairs({ "manual", "treesitter" }) do
  test("Mermaid fence labels are case-insensitive with " .. method, function()
    local buf = reset()
    local lines = vim.fn.readfile(root .. "/tests/fixtures/unlabeled.md")
    for _, label in ipairs({ "mermaid", "Mermaid", "MERMAID" }) do
      lines[1] = string.rep(string.char(96), 3) .. label
      api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local found, err = require("siren.blocks").find(buf, method)
      assert(not err, err)
      assert(#found == 1, method .. " failed to locate label " .. label)
    end
  end)
end
test("selection keymap uses the active visual selection", function()
  local buf = reset()
  local f = string.rep(string.char(96), 3)
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    f .. "mermaid", "flowchart LR", "A-->B", f, "",
    f .. "mermaid", "flowchart LR", "C-->D", f,
  })
  api.nvim_win_set_cursor(0, { 7, 0 })
  vim.cmd("normal! Vj")
  local map = vim.fn.maparg("<Space>mv", "x", false, true)
  assert(map.callback, "Missing Visual selection map")
  map.callback()
  assert(vim.wait(15000, function()
    local s = siren.status()
    return not s.busy and s.results and #s.results == 1
  end, 20), "Visual mapping did not render one selected block")
  assert(siren.status().results[1].block.first == 5, "Visual map rendered the wrong block")
  siren.clear()
end)
test("preview stays visible when another plugin conceals the closing fence", function()
  local buf = reset()
  local f = string.rep(string.char(96), 3)
  api.nvim_buf_set_lines(buf, 0, -1, false, { f .. "Mermaid", "flowchart LR", "A-->B", f, "After" })
  vim.wo.conceallevel = 3
  local hidden = api.nvim_create_namespace("siren-test-hidden-fence")
  api.nvim_buf_set_extmark(buf, hidden, 3, 0, { end_row = 4, conceal_lines = "" })
  vim.cmd("Siren all")
  assert(vim.wait(15000, function()
    local s = siren.status()
    return not s.busy and s.results and #s.results == 1
  end, 20), "Renderer did not finish")
  local height = api.nvim_win_text_height(0, { start_row = 0, end_row = 4 })
  assert(height.fill > 0, "Image exists but virtual rows are hidden with the closing fence")
  api.nvim_buf_clear_namespace(buf, hidden, 0, -1)
  require("siren.kitty").resize()
  assert(api.nvim_win_text_height(0, { start_row = 0, end_row = 4 }).fill > 0)
  siren.clear()
end)
print(string.format("Trigger regression tests: %d/%d passed", count - failed, count))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
