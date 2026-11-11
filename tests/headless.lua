local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/lazy/nvim-treesitter"))
local api = vim.api
local blocks = require("siren.blocks")
local links = require("siren.links")
local kitty = require("siren.kitty")
local rm = require("siren")
local messages, requests = {}, {}
vim.notify = function(msg) messages[#messages + 1] = msg end
kitty._write = function(data) requests[#requests + 1] = data end
local testdir = root .. "/.test-output"
vim.fn.mkdir(testdir, "p")
local fence = string.rep(string.char(96), 3)
local function eq(a, b) assert(vim.deep_equal(a, b), vim.inspect(a) .. " ~= " .. vim.inspect(b)) end
local count = 0
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n"); vim.cmd("cquit 1") end
  count = count + 1
  print("PASS " .. name)
end
local function buffer(name, lines)
  local b = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(b)
  api.nvim_buf_set_name(b, testdir .. "/" .. name)
  vim.bo[b].filetype = "markdown"
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end
local function wait()
  assert(vim.wait(15000, function()
    local s = rm._sessions[api.nvim_get_current_buf()]
    return s and not s.busy and #s.results > 0
  end, 20), table.concat(messages, "\n"))
end
local function config(opts)
  rm.setup(vim.tbl_extend("force", { parser = "manual", debounce_ms = 20, cache_dir = testdir .. "/cache" }, opts or {}))
end
test("manual fences respect nesting, tilde, indentation and incomplete blocks", function()
  local found, err = blocks.scan({ fence .. string.char(96) .. "md", fence .. "mermaid", "A", fence,
    fence .. string.char(96), "  ~~~mermaid", "  flowchart LR", "  A-->B", "  ~~~~",
    fence .. "mermaid", "flowchart LR" })
  eq(#found, 1); eq(found[1].first, 5); eq(found[1].last, 8)
  eq(found[1].source, "flowchart LR\nA-->B")
  assert(err:find("Unclosed"))
end)
test("Tree-sitter extracts content without Mermaid parser", function()
  local b = buffer("treesitter.md", { "text", fence .. "mermaid", "flowchart LR", " A-->B", fence })
  local found, err, method = blocks.find(b, "treesitter")
  assert(not err, err); eq(method, "treesitter"); eq(#found, 1)
  eq(found[1].source, "flowchart LR\n A-->B"); eq(found[1].last, 4)
end)
test("managed links replace idempotently and preserve hand-written links", function()
  local b = buffer("links.md", { fence .. "mermaid", "flowchart LR", "A-->B", fence, "![Mine](mine.png)" })
  local block = blocks.find(b, "manual")[1]
  links.set(b, block, testdir .. "/.siren/a.png")
  local once = api.nvim_buf_get_lines(b, 0, -1, false)
  links.set(b, block, testdir .. "/.siren/a.png")
  eq(api.nvim_buf_get_lines(b, 0, -1, false), once)
  links.clear(b, { block })
  eq(api.nvim_buf_get_lines(b, 0, -1, false)[5], "![Mine](mine.png)")
  api.nvim_buf_set_lines(b, 4, 4, false, { "<!-- render-mermaid:begin -->", "![old](old.png)", "<!-- render-mermaid:end -->" })
  assert(links.after(b, block), "Legacy markers should remain recognizable")
  links.set(b, block, testdir .. "/.siren/new.png")
  eq(api.nvim_buf_get_lines(b, 4, 5, false)[1], links.start)
  links.clear(b, { block })
  eq(api.nvim_buf_get_lines(b, 0, -1, false)[5], "![Mine](mine.png)")
end)
test("native pipeline preserves source and deletes owned images only", function()
  config()
  local lines = { fence .. "mermaid", "flowchart LR", "A[中文]-->B[完成]", fence }
  local b = buffer("native.md", lines)
  api.nvim_win_set_cursor(0, { 2, 0 })
  rm.render("current"); wait()
  eq(api.nvim_buf_get_lines(b, 0, -1, false), lines)
  assert(#api.nvim_buf_get_extmarks(b, kitty.ns, 0, -1, {}) > 0)
  local s = rm.status()
  assert(s.results[1].image.width > 0)
  local meta = vim.json.decode(table.concat(vim.fn.readfile(s.results[1].image.path:gsub("%.png$", ".json")), "\n"))
  local observed = false
  for _, origin in ipairs(meta.origins) do
    if origin.path == api.nvim_buf_get_name(b) then observed = true end
  end
  assert(observed, "Metadata should include the current document, preserving historical origins")
  rm.clear(); eq(next(kitty.placements), nil)
  for _, req in ipairs(requests) do assert(not req:find("d=A", 1, true)) end
end)
test("async edit renders latest source and disable rejects late results", function()
  config()
  local b = buffer("race.md", { fence .. "mermaid", "flowchart LR", "A-->B", fence })
  api.nvim_win_set_cursor(0, { 2, 0 })
  rm.render("current")
  api.nvim_buf_set_lines(b, 2, 3, false, { "A-->C" })
  wait(); eq(rm.status().results[1].block.source, "flowchart LR\nA-->C")
  rm.render("current"); rm.disable()
  vim.wait(500, function() return false end, 20)
  eq(rm.status().enabled, false); eq(next(kitty.placements), nil)
end)
test("all and range scopes select the right blocks", function()
  config()
  buffer("scopes.md", { fence .. "mermaid", "flowchart LR", "A-->B", fence,
    "text", "~~~mermaid", "sequenceDiagram", "A->>B: hi", "~~~" })
  rm.render("selection", { 6, 7 }); wait()
  eq(#rm.status().results, 1); eq(rm.status().results[1].block.first, 5)
  rm.render("all"); wait(); eq(#rm.status().results, 2)
end)
test("Snacks links update, fail cleanly, and repair rename", function()
  config({ snacks_preview = true })
  _G.Snacks = { image = { hover = function() end, image = { new = function() return { placements = {} } end } } }
  local b = buffer("snacks.md", { fence .. "mermaid", "flowchart LR", "A-->B", fence, "![Manual](mine.png)" })
  api.nvim_win_set_cursor(0, { 2, 0 })
  rm.render("all"); wait()
  assert(links.after(b, blocks.find(b, "manual")[1])); eq(next(kitty.placements), nil)
  api.nvim_buf_set_lines(b, 2, 3, false, { "A-->C" })
  api.nvim_exec_autocmds("TextChanged", { buffer = b })
  assert(vim.wait(15000, function()
    local s = rm.status()
    return not s.busy and s.results[1] and s.results[1].block.source:find("A-->C", 1, true)
  end, 20))
  local moved = testdir .. "/moved/snacks.md"
  vim.fn.mkdir(vim.fs.dirname(moved), "p")
  api.nvim_buf_set_name(b, moved)
  api.nvim_exec_autocmds("BufFilePost", { buffer = b })
  assert(vim.wait(15000, function()
    local s = rm.status()
    return not s.busy and s.results[1] and s.results[1].image.path:find("/moved/", 1, true)
  end, 20))
  api.nvim_buf_set_lines(b, 1, 3, false, { "not valid mermaid" })
  api.nvim_exec_autocmds("TextChanged", { buffer = b })
  assert(vim.wait(15000, function()
    return not rm.status().busy and #links.groups(api.nvim_buf_get_lines(b, 0, -1, false)) == 0
  end, 20))
  assert(table.concat(api.nvim_buf_get_lines(b, 0, -1, false), "\n"):find("![Manual](mine.png)", 1, true))
end)
test("floating preview fits after resize and closes cleanly", function()
  config()
  local b = buffer("float.md", { fence .. "mermaid", "flowchart LR", "A-->B", fence })
  api.nvim_win_set_cursor(0, { 2, 0 }); rm.float()
  assert(vim.wait(15000, function()
    local s = rm._sessions[b]; return s and s.float_place ~= nil
  end, 20))
  local s = rm._sessions[b]
  local win = s.float_win
  assert(api.nvim_win_is_valid(win))
  local fb = api.nvim_win_get_buf(win)
  assert(api.nvim_buf_line_count(fb) > 1, "Float needs real rows for placeholders")
  api.nvim_win_set_width(win, 20); kitty.resize()
  assert(s.float_place.cols <= 20)
  api.nvim_buf_delete(fb, { force = true }); eq(s.float_place, nil)
  api.nvim_set_current_buf(b); rm.clear()
end)
print("Passed " .. count .. " headless tests")
vim.cmd("qa!")
