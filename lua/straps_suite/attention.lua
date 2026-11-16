local M = {}
local done = {}
local focused = true

local function visible(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return true end
  end
  return false
end

local function top(buf)
  return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf)
    and vim.b[buf].straps_session == true and vim.b[buf].straps_parent == nil
end

local function redraw()
  vim.schedule(function() vim.cmd.redrawstatus({ bang = true }) end)
end

local function clear_visible()
  if not focused then return end
  for buf in pairs(done) do
    if not top(buf) or visible(buf) then done[buf] = nil end
  end
  redraw()
end

function M.counts()
  local running, waiting = 0, 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if top(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.b[buf].straps_status == 'running' then running = running + 1 end
  end
  for buf in pairs(done) do
    if top(buf) then waiting = waiting + 1 else done[buf] = nil end
  end
  return { running = running, waiting = waiting }
end

function M.status()
  local counts, parts = M.counts(), {}
  if counts.running > 0 then parts[#parts + 1] = counts.running .. ' working' end
  if counts.waiting > 0 then parts[#parts + 1] = counts.waiting .. ' waiting' end
  return table.concat(parts, ' ')
end

function M.setup()
  local group = vim.api.nvim_create_augroup('straps_suite_attention', { clear = true })
  vim.api.nvim_create_autocmd('User', { group = group, pattern = 'StrapsRunStart', callback = function(ev)
    local buf = ev.data and ev.data.bufnr
    if buf then done[buf] = nil end
    redraw()
  end })
  vim.api.nvim_create_autocmd('User', { group = group, pattern = 'StrapsRunEnd', callback = function(ev)
    local data = ev.data or {}
    local buf = data.bufnr
    if top(buf) then
      if data.cancelled == true or data.reason == 'cancelled' or focused and visible(buf) then done[buf] = nil else done[buf] = data.reason or 'done' end
    end
    redraw()
  end })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, { group = group, callback = function(ev)
    if focused and done[ev.buf] then done[ev.buf] = nil; redraw() end
  end })
  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, { group = group, callback = function(ev)
    done[ev.buf] = nil
    redraw()
  end })
  vim.api.nvim_create_autocmd('FocusLost', { group = group, callback = function() focused = false end })
  vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = function() focused = true; clear_visible() end })
  vim.api.nvim_create_autocmd('TabEnter', { group = group, callback = clear_visible })
end

return M
