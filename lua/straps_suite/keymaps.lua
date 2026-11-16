local M = {}

local global = {
  { 'n', '<cmd>Straps<CR>', 'new session (split)' },
  { 'v', '<cmd>vertical Straps<CR>', 'new session (vsplit)' },
  { 't', function() require('straps.ui').open_session('tab split') end, 'new session (tab)' },
  { 'r', '<cmd>StrapsResume<CR>', 'resume latest (split)' },
  { 'V', '<cmd>vertical StrapsResume<CR>', 'resume latest (vsplit)' },
  { 'T', function() require('straps.ui').resume_session(nil, 'tab split') end, 'resume latest (tab)' },
  { 'R', '<cmd>StrapsResume!<CR>', 'resume session (picker)' },
  { 'a', '<cmd>StrapsAgents<CR>', 'agents buffer' },
  { 's', ':StrapsSearch ', 'search transcripts' },
  { 'm', '<cmd>StrapsModel<CR>', 'pick model' },
  { 'e', '<cmd>StrapsEffort<CR>', 'pick effort' },
  { 'p', '<cmd>StrapsProvider<CR>', 'pick provider' },
}
local controls = {
  { 'x', '<cmd>StrapsStop<CR>', 'stop run' },
  { 'c', '<cmd>StrapsContinue<CR>', 'continue run' },
  { 'g', ':StrapsSteer ', 'steer run' },
  { 'k', '<cmd>StrapsCompact<CR>', 'compact session' },
  { 'N', '<cmd>StrapsRename<CR>', 'rename session' },
  { 'u', ':StrapsAuto ', 'auto permissions' },
}

local function install(prefix, mappings, buf)
  local function apply()
    for _, mapping in ipairs(mappings) do
      local key = prefix .. mapping[1]
      local existing = false
      if buf then
        existing = vim.fn.maparg(key, 'n') ~= ''
      else
        local expanded = key:gsub('<leader>', function() return vim.g.mapleader or '\\' end)
          :gsub('<localleader>', function() return vim.g.maplocalleader or '\\' end)
        local lhs = vim.api.nvim_replace_termcodes(expanded, true, true, true)
        for _, mapping_info in ipairs(vim.api.nvim_get_keymap('n')) do
          if vim.api.nvim_replace_termcodes(mapping_info.lhs, true, true, true) == lhs then existing = true; break end
        end
      end
      if not existing then
        local opts = { desc = 'Straps: ' .. mapping[3] }
        if buf then opts.buffer = buf end
        vim.keymap.set('n', key, mapping[2], opts)
      end
    end
  end
  if buf then vim.api.nvim_buf_call(buf, apply) else apply() end
end

function M.setup(prefix)
  if prefix == false then return end
  install(prefix, global)
  local group = vim.api.nvim_create_augroup('straps_suite_keymaps', { clear = true })
  vim.api.nvim_create_autocmd('FileType', { group = group, pattern = 'straps', callback = function(ev)
    install(prefix, controls, ev.buf)
  end })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'straps' then install(prefix, controls, buf) end
  end
  local ok, wk = pcall(require, 'which-key')
  if ok and type(wk.add) == 'function' then wk.add({ { prefix, group = 'straps' } }) end
end

return M
