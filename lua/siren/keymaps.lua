local M = {}
local owned = {}
local modes = { current = "n", all = "n", selection = "x", float = "n", clear = "n" }
local descriptions = {
  current = "Siren: render current Mermaid block", all = "Siren: render all Mermaid blocks",
  selection = "Siren: render selected Mermaid blocks", float = "Siren: preview Mermaid in a float",
  clear = "Siren: clear Mermaid previews",
}

function M.clear()
  for buf, records in pairs(owned) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, record in ipairs(records) do
        -- Do not remove a mapping the user replaced after Siren attached.
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, record.mode)) do
          if mapping.callback == record.callback then
            pcall(vim.keymap.del, record.mode, mapping.lhs, { buffer = buf })
          end
        end
      end
    end
  end
  owned = {}
end

function M.setup(config, group, actions)
  M.clear()
  if config == false then return end
  local function attach(buf)
    if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "markdown" or owned[buf] then return end
    owned[buf] = {}
    for action, mode in pairs(modes) do
      local lhs = config[action]
      if type(lhs) == "string" and lhs ~= "" then
        local callback = actions[action]
        vim.keymap.set(mode, lhs, callback, {
          buffer = buf, silent = true, desc = descriptions[action],
        })
        owned[buf][#owned[buf] + 1] = { mode = mode, callback = callback }
      end
    end
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group, pattern = "markdown", callback = function(ev) attach(ev.buf) end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group, callback = function(ev) owned[ev.buf] = nil end,
  })
  -- lazy.nvim can invoke setup during the initial FileType event.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do attach(buf) end
end
return M
