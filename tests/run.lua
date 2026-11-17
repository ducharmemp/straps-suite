local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local checks = 0
local function check(value, message)
  checks = checks + 1
  if tonumber(vim.env.STRAPS_SUITE_NEGATE) == checks then value = not value end
  assert(value, message)
end
local function rejects(fn, text)
  local ok, err = pcall(fn)
  check(not ok and tostring(err):find(text, 1, true) ~= nil, 'expected refusal: ' .. text)
end
local config = require('straps_suite.config')
local cfg = config.resolve()
check(cfg.core.max_spawn_depth == 4, 'spawn depth')
check(cfg.core.context_management.enabled == false, 'context disabled by default')
check(cfg.core.context_management.mode == 'mechanical', 'mechanical mode')
check(cfg.core.context_management.trigger == 0.85, 'trigger')
check(cfg.core.context_management.target == 0.7, 'target')
check(cfg.core.context_management.reserve_tokens == 4096, 'retrieval reserve')
check(cfg.core.auto_compact_tokens == nil and cfg.core.auto_compact_bytes == nil, 'legacy thresholds unset')
check(cfg.extensions.renamer.auto.enabled == false, 'automatic rename disabled')
check(cfg.extensions.classifier.cutoffs == nil, 'no personal hazard bypass')
check(cfg.extensions.classifier.ask_cutoffs.fairness == 2, 'question cutoff')
local override = config.resolve({ core = { context_management = { enabled = true } }, extensions = { renamer = false } })
check(override.core.context_management.enabled == true, 'enable context')
check(override.core.context_management.mode == 'mechanical', 'enabling context keeps mechanical mode')
check(override.extensions.renamer == false, 'disable extension')
rejects(function() config.resolve({ wrong = true }) end, 'unknown option')
rejects(function() config.resolve({ extensions = { wrong = {} } }) end, 'unknown extension')
rejects(function() config.resolve({ extensions = { kagi = true } }) end, 'must be false or a table')
rejects(function() config.resolve({ keymaps = '' }) end, 'nonempty prefix')
rejects(function() config.resolve({ attention = 'yes' }) end, 'must be boolean')
rejects(function() config.resolve({ extensions = { buff = false }, browser = { headless = true } }) end, 'require the Buff extension')
rejects(function() config.resolve(false) end, 'must be a table')

local calls, frozen, install_failure, setup_error = {}, false, false, false
package.loaded['straps.registry'] = { trusted_setup_allowed = function() return not frozen end }
package.loaded.straps = { setup = function(opts) calls[#calls + 1] = 'core'; package.loaded.straps.config = opts end }
package.loaded['straps.context_management'] = { account = function() end }
package.loaded['buff.api'] = { version = function() return 1 end, client = function() error('must not start') end }
package.loaded.buff = { setup = function(opts) calls[#calls + 1] = 'browser'; check(opts.headless == true, 'browser opts') end }
for _, item in ipairs(config.modules) do
  local name = item[1]
  package.loaded[item[2]] = { installed = true, setup = function(opts)
    calls[#calls + 1] = name
    if setup_error then error('setup exploded') end
    if name == 'renamer' then check(opts.auto.enabled == false, 'rename opts reach module') end
    if name == 'classifier' and install_failure then package.loaded.straps_classifier.installed = false end
  end }
end
local function fresh()
  package.loaded.straps_suite = nil
  vim.g.loaded_straps_chartifier = nil
  vim.g.loaded_straps_renamer = nil
  return require('straps_suite')
end
local opts = { browser = { headless = true }, keymaps = false, attention = false }
local suite = fresh()
suite.prepare(opts)
check(vim.g.loaded_straps_chartifier == true and vim.g.loaded_straps_renamer == true, 'automatic plugin scripts suppressed')
rejects(function() suite.setup({ attention = false }) end, 'configuration changed')
suite.setup(opts)
check(calls[1] == 'core' and calls[2] == 'browser', 'core/browser setup order')
check(calls[#calls] == 'classifier', 'classifier after extensions')
check(package.loaded.straps.config.context_management.enabled == false, 'context passed to core')
local count = #calls
suite.setup(opts)
check(#calls == count, 'repeat setup does not call dependencies')
local status = suite.status()
status.configuration.core.max_spawn_depth = 99
check(suite.status().configuration.core.max_spawn_depth == 4, 'status configuration isolated')
check(status.configured == true, 'completed state')
suite = fresh()
vim.g.loaded_straps_renamer = true
rejects(function() suite.prepare(opts) end, 'before chartifier and renamer')
check(not vim.g.loaded_straps_chartifier, 'late prepare makes no partial suppression')
suite = fresh()
frozen = true
rejects(function() suite.setup(opts) end, 'precede sessions')
check(not suite.status().prepared, 'preflight failure precedes mutation')
frozen = false
package.loaded['buff.api'].version = function() return 2 end
rejects(function() suite.setup(opts) end, 'Buff API v1')
package.loaded['buff.api'].version = function() return 1 end
install_failure = true
rejects(function() suite.setup(opts) end, 'classifier installation failed')
rejects(function() suite.setup(opts) end, 'previous setup failed')
check(suite.status().configured == false, 'failed setup incomplete')
install_failure = false
package.loaded.straps_classifier.installed = true
suite = fresh()
setup_error = true
rejects(function() suite.setup(opts) end, 'setup exploded')
check(suite.status().failure:find('setup exploded', 1, true) ~= nil, 'partial failure recorded')
setup_error = false
suite = fresh()
local disabled = {}
for _, item in ipairs(config.modules) do disabled[item[1]] = false end
calls = {}
suite.setup({ extensions = disabled, keymaps = false, attention = false })
check(#calls == 1 and calls[1] == 'core', 'disabled extensions not configured')

vim.g.mapleader = ','
vim.keymap.set('n', ',tn', '<cmd>echo "existing"<CR>')
vim.keymap.set('n', ',tv', 'local-only', { buffer = 0 })
local session = vim.api.nvim_create_buf(true, false)
vim.bo[session].filetype = 'straps'
local wk
package.loaded['which-key'] = { add = function(value) wk = value end }
require('straps_suite.keymaps').setup('<leader>t')
check(vim.fn.maparg(',tn', 'n'):find('existing', 1, true) ~= nil, 'preserve global mapping')
check(vim.fn.maparg(',tv', 'n') == 'local-only', 'preserve current buffer mapping')
vim.api.nvim_buf_call(session, function()
  check(vim.fn.maparg(',tv', 'n') == '<Cmd>vertical Straps<CR>', 'local collision does not suppress global vsplit mapping')
end)
check(wk[1][1] == '<leader>t', 'which-key prefix')
vim.api.nvim_buf_call(session, function()
  check(vim.fn.maparg(',tx', 'n', false, true).buffer == 1, 'existing session receives local controls')
end)
local second = vim.api.nvim_create_buf(true, false)
vim.bo[second].filetype = 'straps'
vim.api.nvim_buf_call(second, function() check(vim.fn.maparg(',tc', 'n') == '<Cmd>StrapsContinue<CR>', 'new session controls') end)
check(vim.fn.maparg(',tx', 'n') == '', 'controls not global')
require('straps_suite.keymaps').setup(false)

local attention = require('straps_suite.attention')
attention.setup()
local function event(pattern, data) vim.api.nvim_exec_autocmds('User', { pattern = pattern, data = data }) end
vim.b[session].straps_session, vim.b[session].straps_status = true, 'running'
vim.b[second].straps_session, vim.b[second].straps_status, vim.b[second].straps_parent = true, 'running', session
check(attention.counts().running == 1, 'running excludes child')
check(attention.status() == '1 working', 'working string')
event('StrapsRunEnd', { bufnr = session, reason = 'error' })
check(attention.counts().waiting == 1, 'hidden error waits')
event('StrapsRunStart', { bufnr = session })
check(attention.counts().waiting == 0, 'new run clears waiting')
event('StrapsRunEnd', { bufnr = second, reason = 'ok' })
check(attention.counts().waiting == 0, 'child completion ignored')
event('StrapsRunEnd', { bufnr = session, reason = 'cancelled' })
check(attention.counts().waiting == 0, 'cancel does not wait')
vim.api.nvim_set_current_buf(session)
event('StrapsRunEnd', { bufnr = session, reason = 'ok' })
check(attention.counts().waiting == 0, 'visible focused completion seen')
vim.api.nvim_exec_autocmds('FocusLost', {})
event('StrapsRunEnd', { bufnr = session, reason = 'error', cancelled = true })
check(attention.counts().waiting == 0, 'cancelled backstop error does not wait')
event('StrapsRunEnd', { bufnr = session, reason = 'ok' })
check(attention.counts().waiting == 1, 'unfocused completion waits')
vim.api.nvim_exec_autocmds('BufEnter', { buffer = session })
check(attention.counts().waiting == 1, 'unfocused buffer enter retains waiting')
vim.api.nvim_exec_autocmds('FocusGained', {})
check(attention.counts().waiting == 0, 'focus sees visible completion')
vim.api.nvim_set_current_buf(1)
event('StrapsRunEnd', { bufnr = session, reason = 'ok' })
vim.api.nvim_buf_delete(session, { force = true })
check(attention.counts().waiting == 0, 'wipe removes waiting')
vim.b[second].straps_status = 'idle'
check(attention.status() == '', 'idle status empty')
local reports = {}
vim.health = {}
for _, severity in ipairs({ 'start', 'ok', 'warn', 'error', 'info' }) do
  vim.health[severity] = function(message) reports[#reports + 1] = severity .. ':' .. message end
end
package.loaded['straps_classifier.health'] = { check = function() reports[#reports + 1] = 'classifier checked' end }
require('straps_suite.health').check()
check(table.concat(reports, '\n'):find('Unknown input allowance blocks dispatch', 1, true) ~= nil, 'health reports unknown budget')
local original_status = suite.status
suite.status = function() return { configured = true, configuration = config.resolve({ core = {
  context_management = { mode = 'summary', context_limit = 10000 } } }) } end
reports = {}
require('straps_suite.health').check()
check(table.concat(reports, '\n'):find('Summary mode makes provider requests', 1, true) ~= nil, 'health reports summary cost')
check(table.concat(reports, '\n'):find('Combined context requires an output reservation', 1, true) ~= nil, 'health reports output reserve')
check(table.concat(reports, '\n'):find('classifier checked', 1, true) ~= nil, 'health delegates classifier')
suite.status = original_status
print('straps-suite unit assertions: ' .. checks)
