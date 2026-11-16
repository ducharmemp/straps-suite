local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local root = vim.fn.fnamemodify(script, ':h:h')
local child = vim.env.STRAPS_SUITE_STARTUP_CHILD == '1'
local mode = vim.env.STRAPS_SUITE_MODE or 'defaults'
local negate = tonumber(vim.env.STRAPS_SUITE_NEGATE)
local count = 0
local function check(value, message)
  count = count + 1
  if negate == count then value = not value end
  assert(value, ('startup assertion %d: %s'):format(count, message))
end

if not child then
  local executable = vim.env.STRAPS_SUITE_STARTUP_NVIM or vim.v.progpath
  local function run(which, inversion)
    local temporary = vim.fn.tempname()
    vim.fn.mkdir(temporary, 'p')
    local env = { HOME = temporary, XDG_CONFIG_HOME = temporary .. '/config', XDG_DATA_HOME = temporary .. '/data',
      XDG_STATE_HOME = temporary .. '/state', XDG_CACHE_HOME = temporary .. '/cache', XDG_RUNTIME_DIR = temporary .. '/runtime',
      STRAPS_SUITE_STARTUP_CHILD = '1', STRAPS_SUITE_MODE = which, STRAPS_SUITE_NEGATE = inversion and tostring(inversion) or '' }
    vim.fn.mkdir(env.XDG_RUNTIME_DIR, 'p', 448)
    local command = { executable, '--headless', '-i', 'NONE' }
    if not vim.env.STRAPS_SUITE_STARTUP_NVIM then vim.list_extend(command, { '-u', script }) end
    local result = vim.system(command, { text = true, env = env }):wait(60000)
    vim.fn.delete(temporary, 'rf')
    return result, (result.stdout or '') .. (result.stderr or '')
  end
  local ok, err = xpcall(function()
    for _, which in ipairs(vim.env.STRAPS_SUITE_STARTUP_MODE and { vim.env.STRAPS_SUITE_STARTUP_MODE } or { 'defaults', 'disabled' }) do
      local result, output = run(which, negate)
      assert(result.code == 0, which .. ': ' .. output)
      local total = tonumber(output:match('SUITE_STARTUP_ASSERTIONS=(%d+)'))
      assert(total and total > 0, 'missing startup assertion count: ' .. output)
      if not negate then
        for index = 1, total do
          result, output = run(which, index)
          assert(result.code ~= 0 and output:find('startup assertion ' .. index .. ':', 1, true),
            ('counterfactual %s/%d did not fail at its assertion: %s'):format(which, index, output))
        end
      end
      print(('straps-suite startup %s: %d assertions and counterfactuals passed'):format(which, total))
    end
  end, debug.traceback)
  if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
  vim.cmd('qa!')
  return
end

local errors = {}
local notify = vim.notify
vim.notify = function(message, level, opts)
  if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
  return notify(message, level, opts)
end

if not vim.env.STRAPS_SUITE_STARTUP_NVIM then
  local sources = vim.json.decode((assert(vim.env.STRAPS_SUITE_SOURCES, 'missing STRAPS_SUITE_SOURCES')))
  vim.opt.runtimepath:prepend(assert(vim.env.STRAPS_SUITE_LAZY, 'missing STRAPS_SUITE_LAZY'))
  local dependencies = {}
  for _, name in ipairs({ 'straps', 'buff', 'straps-buff', 'straps-chartifier', 'straps-classifier',
    'straps-divergent', 'straps-exoskeleton', 'straps-kagi', 'straps-renamer' }) do
    dependencies[#dependencies + 1] = { name = name, dir = assert(sources[name]), lazy = true }
  end
  local opts = mode == 'disabled' and { extensions = { chartifier = false, renamer = false } } or {}
  require('lazy').setup({ {
    name = 'straps-suite', dir = root, lazy = false, dependencies = dependencies,
    init = function(plugin)
      vim.opt.runtimepath:prepend(plugin.dir)
      require('straps_suite').prepare(opts)
      vim.g.suite_prepared_before_dependencies = not vim.g.loaded_straps and vim.fn.exists(':BuffStart') == 0
    end,
    config = function() require('straps_suite').setup(opts) end,
  } }, {
    local_spec = false, install = { missing = false }, checker = { enabled = false },
    change_detection = { enabled = false }, rocks = { enabled = false }, pkg = { enabled = false },
    lockfile = vim.fn.stdpath('config') .. '/lazy-lock.json',
  })
end

vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  local ok, err = xpcall(function()
    local registry = require('straps.registry')
    check(vim.v.vim_did_enter == 1, 'assertions run at VimEnter')
    check(#errors == 0 and vim.v.errmsg == '', 'startup has no errors: ' .. table.concat(errors, '; ') .. vim.v.errmsg)
    check(require('straps_suite').status().configured, 'suite configured')
    check(vim.g.suite_prepared_before_dependencies == true, 'prepare precedes dependency plugin scripts')
    if vim.env.STRAPS_SUITE_STARTUP_NVIM then
      check(vim.g.suite_configured_before_dependencies == true, 'Nixvim setup precedes dependency plugin scripts')
    end
    check(vim.g.loaded_straps == true, 'core plugin script loaded')
    check(vim.fn.exists(':BuffStart') == 2, 'Buff plugin script loaded')
    check(vim.g.loaded_straps_chartifier == true, 'chartifier automatic setup suppressed')
    check(vim.g.loaded_straps_renamer == true, 'renamer automatic setup suppressed')
    for _, marker in ipairs({ 'tool.fork', 'tool.collab_start', 'tool.buff_operate', 'tool.search', 'hook.guard.classifier' }) do
      check(registry.get(marker) ~= nil, 'registered ' .. marker)
    end
    check(require('buff').state() == 'stopped', 'no browser started')
    if mode == 'disabled' then
      check(registry.get('tool.show_chart') == nil, 'disabled chartifier has no tool')
      check(registry.get('fn.renamer_excerpt') == nil, 'disabled renamer has no function')
      check(vim.fn.exists(':StrapsRenameAuto') == 0, 'disabled renamer has no command')
      local automatic = vim.tbl_filter(function(item) return item.group_name == 'straps_renamer_auto' end,
        vim.api.nvim_get_autocmds({ event = 'User', pattern = 'StrapsRunStart' }))
      check(#automatic == 0, 'disabled renamer has no run-start autocmd')
    else
      check(registry.get('tool.show_chart') ~= nil, 'chartifier tool registered')
      check(registry.get('fn.renamer_excerpt') ~= nil, 'renamer function registered')
      check(require('straps_renamer').config.auto.enabled == false, 'automatic renaming disabled by default')
    end
    check(vim.fn.filereadable(vim.fn.stdpath('config') .. '/lazy-lock.json') == 0, 'no lazy lock file written')
    print('SUITE_STARTUP_ASSERTIONS=' .. count)
  end, debug.traceback)
  if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
  vim.cmd('qa!')
end })
