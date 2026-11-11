local M = {}

local function fence(line)
  local indent, run, tail = line:match("^( *)([~]+)(.*)$")
  if not run then indent, run, tail = line:match("^( *)([\x60]+)(.*)$") end
  if not run or #indent > 3 or #run < 3 then return end
  return run:sub(1, 1), #run, vim.trim(tail), #indent
end

local function is_close(line, char, length)
  local c, n, tail = fence(line)
  return c == char and n >= length and tail == ""
end

-- Deliberately scan all fences: a Mermaid-looking example inside another
-- code block must not be interpreted as a real diagram.
function M.scan(lines)
  local blocks, open = {}, nil
  for i, line in ipairs(lines) do
    if open then
      if is_close(line, open.char, open.length) then
        if open.mermaid then
          local content = {}
          for j = open.first + 2, i - 1 do
            content[#content + 1] = lines[j]:gsub("^" .. string.rep(" ", open.indent), "", 1)
          end
          blocks[#blocks + 1] = { first = open.first, last = i - 1, source = table.concat(content, "\n") }
        end
        open = nil
      end
    else
      local char, length, info, indent = fence(line)
      if char and not (char == "\x60" and info:find("\x60", 1, true)) then
        open = { char = char, length = length, first = i - 1, indent = indent,
          mermaid = (info:match("^(%S+)") or ""):lower() == "mermaid" }
      end
    end
  end
  return blocks, open and open.mermaid and ("Unclosed Mermaid fence at line " .. (open.first + 1)) or nil
end

local function from_tree(buf, lines)
  local parser = vim.treesitter.get_parser(buf, "markdown")
  local trees = parser:parse()
  local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @block")
  local result, problem = {}, nil
  for _, tree in ipairs(trees) do
    for _, node in query:iter_captures(tree:root(), buf, 0, -1) do
      local lang, content, delimiters = nil, "", 0
      for child in node:iter_children() do
        local kind = child:type()
        if kind == "info_string" then lang = vim.treesitter.get_node_text(child, buf):match("^(%S+)") end
        if kind == "code_fence_content" then content = vim.treesitter.get_node_text(child, buf):gsub("\n$", "") end
        if kind == "fenced_code_block_delimiter" then delimiters = delimiters + 1 end
      end
      if lang and lang:lower() == "mermaid" then
        local first, _, last, col = node:range()
        if col == 0 then last = last - 1 end
        if delimiters < 2 then
          problem = "Unclosed Mermaid fence at line " .. (first + 1)
        else
          result[#result + 1] = { first = first, last = last, source = content }
        end
      end
    end
  end
  return result, problem
end

function M.find(buf, method)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if method ~= "manual" then
    local ok, result, problem = pcall(from_tree, buf, lines)
    if ok then return result, problem, "treesitter" end
    if method == "treesitter" then return {}, "Markdown Tree-sitter unavailable: " .. tostring(result) end
  end
  local result, problem = M.scan(lines)
  return result, problem, "manual"
end
return M
