local M = { placements = {}, ns = vim.api.nvim_create_namespace("siren.images") }
local seq, resize_ticket = 0, 0
local positions = {}
-- First 128 entries of Kitty's protocol-defined row/column diacritic table.
local codes = "0305,030D,030E,0310,0312,033D,033E,033F,0346,034A,034B,034C,0350,0351,0352,0357,035B,0363,0364,0365,0366,0367,0368,0369,036A,036B,036C,036D,036E,036F,0483,0484,0485,0486,0487,0592,0593,0594,0595,0597,0598,0599,059C,059D,059E,059F,05A0,05A1,05A8,05A9,05AB,05AC,05AF,05C4,0610,0611,0612,0613,0614,0615,0616,0617,0657,0658,0659,065A,065B,065D,065E,06D6,06D7,06D8,06D9,06DA,06DB,06DC,06DF,06E0,06E1,06E2,06E4,06E7,06E8,06EB,06EC,0730,0732,0733,0735,0736,073A,073D,073F,0740,0741,0743,0745,0747,0749,074A,07EB,07EC,07ED,07EE,07EF,07F0,07F1,07F3,0816,0817,0818,0819,081B,081C,081D,081E,081F,0820,0821,0822,0823,0825,0826,0827,0829,082A,082B,082C,082D,0951"
for _, code in ipairs(vim.split(codes, ",")) do positions[#positions + 1] = vim.fn.nr2char(tonumber(code, 16)) end
local placeholder = vim.fn.nr2char(0x10EEEE)
local bit = require("bit")

function M.supported()
  return not vim.env.SSH_CONNECTION and not vim.env.TMUX
    and ((vim.env.TERM or ""):find("kitty", 1, true) ~= nil or vim.env.KITTY_WINDOW_ID ~= nil)
end

function M.request(params, data)
  local parts = {}
  for k, v in pairs(params) do parts[#parts + 1] = k .. "=" .. tostring(v) end
  parts[#parts + 1] = "q=2"
  local msg = "\27_G" .. table.concat(parts, ",") .. (data and ";" .. data or "") .. "\27\\"
  if M._write then return M._write(msg) end
  if #vim.api.nvim_list_uis() == 0 then return end
  if vim.api.nvim_ui_send then vim.api.nvim_ui_send(msg) else io.stdout:write(msg); io.stdout:flush() end
end

function M.cell()
  local cw, ch = 9, 18
  pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, [[typedef struct { unsigned short row,col,xpixel,ypixel; } rm_winsize;
      int ioctl(int fd, unsigned long request, ...);]])
    local sz = ffi.new("rm_winsize")
    local fd = vim.uv.fs_open("/dev/tty", "r", 0)
    if fd then
      local ok = ffi.C.ioctl(fd, 0x5413, sz)
      vim.uv.fs_close(fd)
      if ok == 0 and sz.col > 0 and sz.row > 0 and sz.xpixel > 0 then
        cw, ch = sz.xpixel / sz.col, sz.ypixel / sz.row
      end
    end
  end)
  return cw, ch
end

function M.fit(result, width, height)
  local cw, ch = M.cell()
  local scale = math.min(1, width * cw / result.width, height * ch / result.height)
  return math.max(1, math.ceil(result.width * scale / cw)),
    math.max(1, math.ceil(result.height * scale / ch))
end

function M.new(buf, row, result, opts)
  seq = seq + 1
  -- High byte 0x4D keeps these disjoint from Snacks' 24-bit IDs.
  local low = (vim.fn.getpid() * 256 + seq) % 0xFFFFFF + 1
  local id = 0x4D000000 + low
  local p = { id = id, buf = buf, row = row, result = result, opts = opts }
  M.placements[id] = p
  if not opts.float then
    p.anchor = vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, { right_gravity = false })
  end
  M.request({ a = "t", f = 100, t = "f", i = id }, vim.base64.encode(result.path))
  M.update(p)
  M.schedule_resize()
  return p
end

local function concealed(buf, row)
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, {
    details = true, overlap = true,
  })) do
    if mark[4].conceal_lines ~= nil then return true end
  end
  return false
end

function M.update(p)
  if not vim.api.nvim_buf_is_valid(p.buf) then return M.close(p) end
  local width, height = p.opts.max_width, p.opts.max_height
  for _, win in ipairs(vim.fn.win_findbuf(p.buf)) do
    local info = vim.fn.getwininfo(win)[1]
    width = math.min(width, info.width - info.textoff - 1)
    if p.opts.float then height = math.min(height, vim.api.nvim_win_get_height(win)) end
  end
  local cols, rows = M.fit(p.result, math.max(1, width), math.max(1, height))
  cols, rows = math.min(cols, #positions), math.min(rows, #positions)
  local display_row = p.row
  if p.anchor then
    local anchor = vim.api.nvim_buf_get_extmark_by_id(p.buf, M.ns, p.anchor, {})
    if #anchor > 0 then p.row = anchor[1] end
    display_row = p.row
    -- Keep the logical fence anchor, but put pixels after a visible source line.
    -- Virtual lines on a concealed fence disappear along with that fence.
    while display_row > 0 and concealed(p.buf, display_row) do display_row = display_row - 1 end
  end
  if cols == p.cols and rows == p.rows then
    if p.opts.float and p.marks then return end
    if p.mark and p.display_row == display_row
      and #vim.api.nvim_buf_get_extmark_by_id(p.buf, M.ns, p.mark, {}) > 0 then return end
  end
  local hl = "SirenImage" .. p.id
  vim.api.nvim_set_hl(0, hl, { fg = p.id % 0x1000000, nocombine = true })
  M.request({ a = "p", i = p.id, p = 1, U = 1, c = cols, r = rows })
  local grid = {}
  for r = 1, rows do
    local line = {}
    for c = 1, cols do line[#line + 1] = placeholder .. positions[r] .. positions[c] .. positions[0x4D + 1] end
    grid[#grid + 1] = { { table.concat(line), hl } }
  end
  if p.opts.float then
    for _, id in ipairs(p.marks or {}) do pcall(vim.api.nvim_buf_del_extmark, p.buf, M.ns, id) end
    local blank = {}
    for _ = 1, rows do blank[#blank + 1] = "" end
    vim.api.nvim_buf_set_lines(p.buf, 0, -1, false, blank)
    p.marks = {}
    for r, chunks in ipairs(grid) do
      p.marks[#p.marks + 1] = vim.api.nvim_buf_set_extmark(p.buf, M.ns, r - 1, 0, {
        virt_text = chunks, virt_text_pos = "overlay", priority = 200,
      })
    end
    p.cols, p.rows = cols, rows
    return
  end
  local opts = { id = p.mark, virt_lines = grid, virt_lines_above = false,
    right_gravity = false, priority = 200 }
  p.mark = vim.api.nvim_buf_set_extmark(p.buf, M.ns, math.min(display_row, vim.api.nvim_buf_line_count(p.buf) - 1), 0, opts)
  p.display_row = display_row
  p.cols, p.rows = cols, rows
end

function M.close(p)
  if not p or not M.placements[p.id] then return end
  M.placements[p.id] = nil
  M.request({ a = "d", d = "I", i = p.id })
  if vim.api.nvim_buf_is_valid(p.buf) then
    if p.mark then pcall(vim.api.nvim_buf_del_extmark, p.buf, M.ns, p.mark) end
    if p.anchor then pcall(vim.api.nvim_buf_del_extmark, p.buf, M.ns, p.anchor) end
    for _, id in ipairs(p.marks or {}) do pcall(vim.api.nvim_buf_del_extmark, p.buf, M.ns, id) end
  end
end

function M.clear(buf)
  for _, p in pairs(vim.tbl_extend("force", {}, M.placements)) do
    if not buf or p.buf == buf then M.close(p) end
  end
end

function M.schedule_resize()
  resize_ticket = resize_ticket + 1
  local ticket = resize_ticket
  vim.defer_fn(function()
    if ticket == resize_ticket then M.resize() end
  end, 100)
end

function M.resize()
  for _, p in pairs(vim.tbl_extend("force", {}, M.placements)) do M.update(p) end
end
return M
