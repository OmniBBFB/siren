local M = {}
local api, uv = vim.api, vim.uv
M.root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
local blocks = require("siren.blocks")
local links = require("siren.links")
local kitty = require("siren.kitty")
local ns = api.nvim_create_namespace("siren.tracking")
local sessions, errors = {}, {}
M._sessions = sessions
local defaults = {
  node = "node", parser = "auto", auto_start = false,
  snacks_preview = false, debounce_ms = 300,
  font = "Noto Sans CJK SC", font_size = 16, scale = 2, colors = {},
  max_width = 100, max_height = 24,
  cache_dir = vim.fn.stdpath("cache") .. "/siren",
  timeout_ms = 30000,
  keymaps = {
    current = "<leader>mc", all = "<leader>ma", selection = "<leader>mv",
    float = "<leader>mf", clear = "<leader>mx",
  },
}
M.config = vim.deepcopy(defaults)
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.ERROR, { title = "Siren" })
end
local function fail(buf, msg)
  if errors[buf] ~= msg then errors[buf] = msg; notify(msg) end
end
local function mark(buf, r)
  return api.nvim_buf_set_extmark(buf, ns, r, 0, { right_gravity = true })
end
local function row(buf, id)
  return api.nvim_buf_get_extmark_by_id(buf, ns, id, {})[1]
end
local function close_float(s)
  if s.float_place then kitty.close(s.float_place); s.float_place = nil end
  if s.float_win and api.nvim_win_is_valid(s.float_win) then pcall(api.nvim_win_close, s.float_win, true) end
  s.float_win = nil
end
local function directory(buf)
  if not M.config.snacks_preview then return M.config.cache_dir end
  local name = api.nvim_buf_get_name(buf)
  if name == "" then return nil, "Snacks preview requires a named Markdown file" end
  return vim.fs.dirname(name) .. "/.siren"
end
local function selected(s, found)
  if s.scope == "all" then return found end
  local chosen = {}
  for _, b in ipairs(found) do
    for _, anchor in ipairs(s.anchors) do
      if row(s.buf, anchor) == b.first then chosen[#chosen + 1] = b; break end
    end
  end
  return chosen
end
local function same(a, b)
  if #a ~= #b then return false end
  for i, item in ipairs(a) do if item.source ~= b[i].source then return false end end
  return true
end
local refresh
local function schedule(s)
  s.ticket = s.ticket + 1
  local ticket = s.ticket
  vim.defer_fn(function()
    if sessions[s.buf] == s and s.ticket == ticket then refresh(s) end
  end, M.config.debounce_ms)
end

local function native_float(s, result)
  if not s.float_win or not api.nvim_win_is_valid(s.float_win) then
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local w = math.max(1, math.floor(vim.o.columns * 0.8))
    local h = math.max(1, math.floor((vim.o.lines - 4) * 0.8))
    s.float_win = api.nvim_open_win(buf, true, {
      relative = "editor", style = "minimal", border = "rounded",
      width = w, height = h, row = math.max(0, math.floor((vim.o.lines - h - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - w - 2) / 2)),
      title = " Mermaid ", title_pos = "center",
    })
    for _, key in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", key, function() s.float_anchor = nil; close_float(s) end, { buffer = buf })
    end
    api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = function()
      if s.float_place then kitty.close(s.float_place); s.float_place = nil end
      s.float_win, s.float_anchor = nil, nil
    end })
  end
  if s.float_place then kitty.close(s.float_place) end
  local buf = api.nvim_win_get_buf(s.float_win)
  s.float_place = kitty.new(buf, 0, result, {
    float = true, max_width = api.nvim_win_get_width(s.float_win),
    max_height = api.nvim_win_get_height(s.float_win),
  })
end
local function snacks_float(s, b)
  local group = links.after(s.buf, b)
  local wins = vim.fn.win_findbuf(s.buf)
  if not group or #wins == 0 then return end
  local win = wins[1]
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, { group.first + 2, 0 })
  Snacks.image.hover()
end
local function display(s, chosen, results)
  kitty.clear(s.buf)
  s.results = {}
  local float_target = s.float_anchor and row(s.buf, s.float_anchor)
  local float_result
  s.mutating = true
  for i = #chosen, 1, -1 do
    local b, result = chosen[i], results[i]
    if result.ok then
      errors[s.buf] = nil
      s.results[#s.results + 1] = { block = b, image = result }
      if M.config.snacks_preview then links.set(s.buf, b, result.path)
      elseif s.inline then kitty.new(s.buf, b.last, result, {
        max_width = M.config.max_width, max_height = M.config.max_height,
      }) end
      if b.first == float_target then float_result = result end
    else
      if M.config.snacks_preview then links.set(s.buf, b, nil) end
      fail(s.buf, "Mermaid at line " .. (b.first + 1) .. ": " .. result.error)
    end
  end
  s.mutating = false
  if float_target and float_result then
    if M.config.snacks_preview then
      if s.open_float then
        for _, b in ipairs(blocks.find(s.buf, M.config.parser)) do
          if b.first == row(s.buf, s.float_anchor) then snacks_float(s, b); break end
        end
      end
    else native_float(s, float_result) end
  elseif float_target then close_float(s) end
  s.open_float = false
  if M.config.snacks_preview then M._fit_snacks(s) end
end
refresh = function(s)
  if sessions[s.buf] ~= s or not api.nvim_buf_is_valid(s.buf) then return end
  if s.busy then s.pending = true; return end
  local found, problem = blocks.find(s.buf, M.config.parser)
  if problem then fail(s.buf, problem) end
  if M.config.snacks_preview then
    s.mutating = true
    links.clean_orphans(s.buf, found)
    s.mutating = false
    found = blocks.find(s.buf, M.config.parser)
  end
  local chosen = selected(s, found)
  if #chosen == 0 then kitty.clear(s.buf); close_float(s); s.results = {}; return end
  local dir, err = directory(s.buf)
  if not dir then return fail(s.buf, err) end
  local jobs = {}
  for _, b in ipairs(chosen) do
    jobs[#jobs + 1] = { source = b.source, directory = dir,
      options = { font = M.config.font, font_size = M.config.font_size,
        scale = M.config.scale, colors = M.config.colors, now = os.date("!%Y-%m-%dT00:00:00Z") },
      origin = { path = api.nvim_buf_get_name(s.buf), block_hash = vim.fn.sha256(b.source), line = b.first + 1 },
    }
  end
  s.busy, s.pending = true, false
  local name = api.nvim_buf_get_name(s.buf)
  s.process = vim.system({ M.config.node, M.root .. "/renderer/worker.mjs" }, {
    stdin = vim.json.encode({ jobs = jobs }), text = true, timeout = M.config.timeout_ms,
  }, function(proc)
    vim.schedule(function()
      if sessions[s.buf] ~= s or not api.nvim_buf_is_valid(s.buf) then return end
      s.busy, s.process = false, nil
      local current = selected(s, blocks.find(s.buf, M.config.parser))
      if not same(chosen, current) or name ~= api.nvim_buf_get_name(s.buf) then schedule(s); return end
      if proc.code ~= 0 then
        kitty.clear(s.buf); close_float(s)
        if M.config.snacks_preview then
          s.mutating = true; links.clear(s.buf, current); s.mutating = false
        end
        fail(s.buf, "Renderer failed: " .. vim.trim(proc.stderr or tostring(proc.code)))
      else
        local ok, response = pcall(vim.json.decode, proc.stdout)
        if not ok or not response.results or #response.results ~= #current then
          fail(s.buf, "Invalid response from renderer")
        else display(s, current, response.results) end
      end
      if s.pending then schedule(s) end
    end)
  end)
end
local function validate(buf)
  if vim.fn.executable(M.config.node) ~= 1 then return nil, "Node executable not found: " .. M.config.node end
  if M.config.snacks_preview then
    if not (_G.Snacks and Snacks.image) then return nil, "snacks_preview requires Snacks.image" end
    if not vim.bo[buf].modifiable or vim.bo[buf].readonly then return nil, "Snacks links require a writable buffer" end
  elseif _G.Snacks and Snacks.image then
    for _, b in ipairs(blocks.find(buf, M.config.parser)) do
      if links.after(buf, b) then
        return nil, "Managed Snacks links already exist; run :Siren clear before switching to native preview"
      end
    end
  end
  if not M.config.snacks_preview and not kitty.supported() and not kitty._write then
    return nil, "Native preview requires local Kitty (no SSH/tmux)"
  end
  return true
end
local function make_session(buf)
  local s = { buf = buf, scope = "current", anchors = {}, ticket = 0, inline = false, results = {} }
  sessions[buf] = s
  return s
end
local function choose(buf, scope, range)
  local found, err = blocks.find(buf, M.config.parser)
  local chosen = {}
  local cursor = api.nvim_win_get_cursor(0)[1] - 1
  for _, b in ipairs(found) do
    if scope == "all" or (scope == "current" and b.first <= cursor and b.last >= cursor)
      or (scope == "selection" and b.first <= range[2] and b.last >= range[1]) then chosen[#chosen + 1] = b end
  end
  if #chosen == 0 and scope ~= "all" then return nil, err or "No complete Mermaid block in the requested range" end
  return chosen, err
end
function M.render(scope, range, opts)
  scope = scope or "current"
  if scope == "float" then return M.float() end
  local buf = api.nvim_get_current_buf()
  local ok, err = validate(buf)
  if not ok then return fail(buf, err) end
  if scope == "selection" then
    range = range or { vim.fn.line("'<") - 1, vim.fn.line("'>") - 1 }
    if range[1] > range[2] then range = { range[2], range[1] } end
  end
  local chosen, problem = choose(buf, scope, range)
  if not chosen then return fail(buf, problem) end
  if #chosen == 0 and not problem and not (opts and opts.silent) then
    notify("No complete mermaid blocks found; add the mermaid language tag to the opening fence.", vim.log.levels.WARN)
  end
  M.disable(buf)
  local s = make_session(buf)
  s.scope, s.inline = scope, true
  for _, b in ipairs(chosen) do s.anchors[#s.anchors + 1] = mark(buf, b.first) end
  refresh(s)
end
function M.float()
  local buf = api.nvim_get_current_buf()
  local ok, err = validate(buf)
  if not ok then return fail(buf, err) end
  local chosen, problem = choose(buf, "current")
  if not chosen then return fail(buf, problem) end
  local s = sessions[buf] or make_session(buf)
  s.float_anchor = mark(buf, chosen[1].first)
  if s.scope ~= "all" then s.anchors[#s.anchors + 1] = s.float_anchor end
  s.open_float = true
  refresh(s)
end
function M.disable(buf)
  buf = buf or api.nvim_get_current_buf()
  local s = sessions[buf]
  sessions[buf], errors[buf] = nil, nil
  if s then
    if s.process then s.process:kill(15) end
    close_float(s)
  end
  kitty.clear(buf)
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
end
function M.clear()
  local buf = api.nvim_get_current_buf()
  local found = blocks.find(buf, M.config.parser)
  local s = sessions[buf]
  local chosen = s and selected(s, found) or found
  M.disable(buf)
  links.clear(buf, chosen)
end
function M.status()
  local s = sessions[api.nvim_get_current_buf()]
  return s and { enabled = true, busy = s.busy or false, scope = s.scope,
    results = vim.deepcopy(s.results), snacks_preview = M.config.snacks_preview } or { enabled = false }
end
function M.prune(days, dry_run)
  local cutoff, removed, protected = os.time() - (days or 30) * 86400, {}, {}
  for _, s in pairs(sessions) do for _, r in ipairs(s.results) do protected[r.image.key] = true end end
  local request = uv.fs_scandir(M.config.cache_dir)
  if request then
    while true do
      local file = uv.fs_scandir_next(request)
      if not file then break end
      local key = file:match("^(%x+)%.json$")
      if key and #key == 64 and not protected[key] then
        local path = M.config.cache_dir .. "/" .. file
        local st = uv.fs_stat(path)
        if st and st.mtime.sec < cutoff and not uv.fs_stat(M.config.cache_dir .. "/" .. key .. ".lock") then
          removed[#removed + 1] = key
          if not dry_run then
            for _, ext in ipairs({ ".json", ".png", ".svg" }) do uv.fs_unlink(M.config.cache_dir .. "/" .. key .. ext) end
          end
        end
      end
    end
  end
  return removed
end
-- Adapt only generated Snacks placements. Snacks computes width including
-- number/sign columns; subtract those to keep diagrams inside the text area.
function M._fit_snacks(s, attempt)
  if sessions[s.buf] ~= s or not M.config.snacks_preview then return end
  local seen = 0
  for _, r in ipairs(s.results) do
    local img = Snacks.image.image.new(r.image.path)
    for _, p in pairs(img.placements) do
      seen = seen + 1
      if not p._siren_fit then
        p._siren_fit = true
        local previous = p.opts.on_update_pre
        p.opts.on_update_pre = function(self)
          if previous then previous(self) end
          local width = M.config.max_width
          for _, win in ipairs(self:wins()) do
            local info = vim.fn.getwininfo(win)[1]
            width = math.min(width, info.width - info.textoff - 1)
          end
          self.opts.max_width = math.max(1, width)
        end
      end
      p:update()
    end
  end
  if seen < #s.results and (attempt or 0) < 10 then
    vim.defer_fn(function() M._fit_snacks(s, (attempt or 0) + 1) end, 150)
  end
end
function M.setup(opts)
  for buf in pairs(vim.tbl_extend("force", {}, sessions)) do M.disable(buf) end
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local group = api.nvim_create_augroup("Siren", { clear = true })
  require("siren.keymaps").setup(M.config.keymaps, group, {
    current = function() M.render("current") end,
    all = function() M.render("all") end,
    selection = function()
      -- Visual mappings execute before '< and '> necessarily reflect this selection.
      local anchor = vim.fn.line("v") - 1
      local cursor = api.nvim_win_get_cursor(0)[1] - 1
      local escape = api.nvim_replace_termcodes("<Esc>", true, false, true)
      api.nvim_feedkeys(escape, "nx", false)
      M.render("selection", { math.min(anchor, cursor), math.max(anchor, cursor) })
    end,
    float = function() M.float() end,
    clear = function() M.clear() end,
  })
  api.nvim_create_user_command("Siren", function(args)
    local action = args.args ~= "" and args.args or (args.range > 0 and "selection" or "current")
    if action == "clear" then M.clear()
    elseif action == "disable" then M.disable()
    elseif action == "status" then notify(vim.inspect(M.status()), vim.log.levels.INFO)
    elseif action == "float" then M.float()
    elseif vim.tbl_contains({ "all", "current", "selection" }, action) then
      M.render(action, args.range > 0 and { args.line1 - 1, args.line2 - 1 } or nil)
    else notify("Unknown action: " .. action) end
  end, { nargs = "?", range = true, force = true, complete = function()
    return { "current", "all", "selection", "float", "clear", "disable", "status" }
  end })
  api.nvim_create_user_command("SirenPrune", function(args)
    local days = args.args == "" and 30 or tonumber(args.args)
    if not days or days < 0 then return notify("Expected a nonnegative number of days") end
    local removed = M.prune(days, not args.bang)
    notify((args.bang and "Removed " or "Would remove ") .. #removed .. " cached images", vim.log.levels.INFO)
  end, { nargs = "?", bang = true, force = true })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufFilePost" }, {
    group = group, callback = function(ev)
      local s = sessions[ev.buf]
      if s and not s.mutating then
        kitty.clear(ev.buf)
        if s.float_place then kitty.close(s.float_place); s.float_place = nil end
        if M.config.snacks_preview then
          local found = selected(s, blocks.find(ev.buf, M.config.parser))
          local known = {}
          for _, r in ipairs(s.results) do known[r.block.source] = true end
          s.mutating = true
          for i = #found, 1, -1 do
            if not known[found[i].source] then links.set(ev.buf, found[i], nil) end
          end
          s.mutating = false
        end
        schedule(s)
      end
    end,
  })
  api.nvim_create_autocmd({ "WinResized", "VimResized", "BufWinEnter" }, {
    group = group, callback = function()
      vim.schedule(function()
        kitty.resize()
        if M.config.snacks_preview then for _, s in pairs(sessions) do M._fit_snacks(s) end end
      end)
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    group = group, callback = function() kitty.schedule_resize() end,
  })
  api.nvim_create_autocmd("WinScrolled", { group = group, callback = function()
    if M.config.snacks_preview then
      for _, s in pairs(sessions) do
        vim.defer_fn(function() M._fit_snacks(s) end, 200)
      end
    end
  end })
  api.nvim_create_autocmd("WinClosed", { group = group, callback = function(ev)
    for _, s in pairs(sessions) do
      if s.float_win == tonumber(ev.match) then
        if s.float_place then kitty.close(s.float_place); s.float_place = nil end
        s.float_win, s.float_anchor = nil, nil
      end
    end
  end })
  api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev) M.disable(ev.buf) end })
  api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function() kitty.clear() end })
  api.nvim_create_autocmd("BufEnter", { group = group, callback = function(ev)
    if M.config.auto_start and vim.bo[ev.buf].filetype == "markdown" and not sessions[ev.buf] then
      vim.schedule(function() if api.nvim_get_current_buf() == ev.buf then M.render("all", nil, { silent = true }) end end)
    end
  end })
end
return M
