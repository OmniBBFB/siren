local M = {}
M.start = "<!-- siren:begin -->"
M.finish = "<!-- siren:end -->"
-- Read old ownership markers so previously generated links can be updated or cleared.
local legacy_start = "<!-- render-mermaid:begin -->"
local legacy_finish = "<!-- render-mermaid:end -->"

function M.groups(lines)
  local result, start = {}, nil
  for i, line in ipairs(lines) do
    if line == M.start or line == legacy_start then start = i - 1
    elseif (line == M.finish or line == legacy_finish) and start then
      result[#result + 1] = { first = start, last = i - 1 }
      start = nil
    end
  end
  return result
end

function M.after(buf, block)
  local lines = vim.api.nvim_buf_get_lines(buf, block.last + 1, block.last + 5, false)
  if (lines[1] == M.start and lines[3] == M.finish)
    or (lines[1] == legacy_start and lines[3] == legacy_finish) then
    return { first = block.last + 1, last = block.last + 3 }
  end
end

function M.set(buf, block, path)
  local group = M.after(buf, block)
  local new = {}
  if path then
    local name = vim.api.nvim_buf_get_name(buf)
    local dir = vim.fs.dirname(name)
    local relative = path:sub(1, #dir + 1) == dir .. "/" and path:sub(#dir + 2) or path
    relative = relative:gsub("%%", "%%25"):gsub(" ", "%%20"):gsub(">", "%%3E"):gsub("<", "%%3C")
    new = { M.start, "![Mermaid preview](<" .. relative .. ">)", M.finish }
  end
  local first = group and group.first or block.last + 1
  local last = group and group.last + 1 or first
  local old = vim.api.nvim_buf_get_lines(buf, first, last, false)
  if not vim.deep_equal(new, old) then
    vim.api.nvim_buf_set_lines(buf, first, last, false, new)
  end
end

function M.clean_orphans(buf, blocks)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local valid = {}
  for _, b in ipairs(blocks) do valid[b.last + 1] = true end
  local groups = M.groups(lines)
  for i = #groups, 1, -1 do
    local g = groups[i]
    if not valid[g.first] then vim.api.nvim_buf_set_lines(buf, g.first, g.last + 1, false, {}) end
  end
end

function M.clear(buf, blocks)
  for i = #blocks, 1, -1 do M.set(buf, blocks[i], nil) end
end
return M
