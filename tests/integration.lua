local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local suite_root = vim.fn.fnamemodify(script, ':h:h')
local names = { 'straps', 'buff', 'straps-buff', 'straps-chartifier', 'straps-classifier', 'straps-divergent',
  'straps-exoskeleton', 'straps-kagi', 'straps-renamer' }
local modes = { 'defaults', 'disabled', 'late', 'conflict' }
local mode = vim.env.STRAPS_SUITE_MODE
local count = 0
local offset = tonumber(vim.env.STRAPS_SUITE_OFFSET) or 0
local negate = tonumber(vim.env.STRAPS_SUITE_NEGATE)

local function check(value, message)
  count = count + 1
  local index = offset + count
  if negate == index then value = not value end
  assert(value, ('integration assertion %d: %s'):format(index, message))
end

local function child(which, start, inversion)
  return vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-l', script }, {
    text = true,
    env = { STRAPS_SUITE_MODE = which, STRAPS_SUITE_OFFSET = tostring(start),
      STRAPS_SUITE_NEGATE = inversion and tostring(inversion) or '' },
  }):wait(60000)
end

local function orchestrate()
  local runs, total = {}, 0
  for _, which in ipairs(modes) do
    local result = child(which, total, negate)
    if result.code ~= 0 then error(which .. ': ' .. (result.stderr or '') .. (result.stdout or '')) end
    local assertions = tonumber(((result.stdout or '') .. (result.stderr or '')):match('SUITE_ASSERTIONS=(%d+)'))
    assert(assertions and assertions > 0, which .. ': missing assertion count')
    runs[#runs + 1] = { mode = which, offset = total, count = assertions }
    total = total + assertions
  end
  assert(not negate or negate >= 1 and negate <= total, 'STRAPS_SUITE_NEGATE is outside assertion range')
  if not negate then
    for _, run in ipairs(runs) do
      for i = 1, run.count do
        local index = run.offset + i
        local result = child(run.mode, run.offset, index)
        local output = (result.stdout or '') .. (result.stderr or '')
        assert(result.code ~= 0 and output:find('integration assertion ' .. index .. ':', 1, true),
          ('assertion negation %d failed to produce its assertion failure: %s'):format(index, output))
      end
    end
  end
  print(('straps-suite integration: %d assertions; %d assertion-negation subprocesses passed'):format(total, negate and 0 or total))
end

local function exercise()
  local temporary = vim.fn.tempname()
  vim.fn.mkdir(temporary, 'p')
  vim.env.HOME = temporary .. '/home'
  for _, kind in ipairs({ 'CONFIG', 'DATA', 'STATE', 'CACHE' }) do
    vim.env['XDG_' .. kind .. '_HOME'] = temporary .. '/' .. kind:lower()
    vim.fn.mkdir(vim.env['XDG_' .. kind .. '_HOME'], 'p')
  end
  vim.env.XDG_RUNTIME_DIR = temporary .. '/runtime'
  vim.fn.mkdir(vim.env.HOME, 'p')
  vim.fn.mkdir(vim.env.XDG_RUNTIME_DIR, 'p', 448)
  local ok, err = xpcall(function()
    local sources
    if vim.env.STRAPS_SUITE_SOURCES and vim.env.STRAPS_SUITE_SOURCES ~= '' then
      sources = vim.json.decode(vim.env.STRAPS_SUITE_SOURCES)
    else
      local eco = vim.env.STRAPS_SUITE_ECO_ROOT or vim.fn.fnamemodify(suite_root, ':h')
      sources = {}
      for _, name in ipairs(names) do sources[name] = eco .. '/' .. name end
      sources.buff = eco .. '/straps-buff/.deps/buff'
    end
    for _, name in ipairs(names) do
      local path = sources[name]
      assert(type(path) == 'string' and vim.fn.isdirectory(path .. '/lua') == 1, 'missing runtime: ' .. name)
      vim.opt.runtimepath:append(path)
    end
    vim.opt.runtimepath:append(suite_root)
    local suite = require('straps_suite')
    if mode == 'late' then
      vim.cmd.source(sources['straps-chartifier'] .. '/plugin/straps_chartifier.lua')
      local accepted, failure = pcall(suite.prepare)
      check(not accepted, 'late preparation must fail')
      check(tostring(failure):find('prepare must run before', 1, true) ~= nil, 'late preparation diagnostic')
      check(not suite.status().prepared, 'late preparation must leave suite unprepared')
      return
    end
    local opts = mode == 'disabled' and { extensions = { chartifier = false, renamer = false } } or {}
    suite.prepare(opts)
    vim.cmd('runtime! plugin/**/*.lua')
    if mode == 'conflict' then
      local accepted, failure = pcall(suite.setup, { core = { compact_keep_turns = 3 } })
      check(not accepted, 'setup must reject changed prepared options')
      check(tostring(failure):find('configuration changed', 1, true) ~= nil, 'conflict diagnostic')
      check(not suite.status().configured, 'conflicting setup must leave suite unconfigured')
      return
    end
    suite.setup(opts)
    local registry = require('straps.registry')
    check(suite.status().configured, 'suite configured after real plugin startup')
    check(vim.g.loaded_straps == true, 'core plugin script loaded')
    check(vim.fn.exists(':BuffStart') == 2, 'Buff plugin script loaded')
    if mode == 'disabled' then
      check(registry.get('tool.show_chart') == nil, 'disabled chartifier has no tool')
      check(registry.get('fn.renamer_excerpt') == nil, 'disabled renamer has no registry functions')
      check(vim.fn.exists(':StrapsRenameAuto') == 0, 'disabled renamer has no command')
      local automatic = vim.tbl_filter(function(autocmd) return autocmd.group_name == 'straps_renamer_auto' end,
        vim.api.nvim_get_autocmds({ event = 'User', pattern = 'StrapsRunStart' }))
      check(#automatic == 0, 'disabled renamer has no run-start autocmd')
      check(require('buff').state() == 'stopped', 'disabled mode does not start Buff')
      return
    end
    for _, marker in ipairs({ 'tool.fork', 'tool.collab_start', 'tool.show_chart', 'tool.buff_operate',
      'tool.search', 'fn.renamer_excerpt', 'hook.guard.classifier' }) do
      check(registry.get(marker) ~= nil, 'extension registry marker ' .. marker)
    end
    check(require('straps_classifier').installed == true, 'classifier installed')
    local renamer = require('straps_renamer')
    check(renamer.config.auto.enabled == false, 'automatic renaming disabled by default')
    local requests, original = 0, renamer.rename
    renamer.rename = function() requests = requests + 1; return false end
    local path = temporary .. '/saved.straps'
    vim.fn.writefile({ '%%[straps:user]%%', 'name this session' }, path)
    local saved = vim.fn.bufadd(path)
    vim.fn.bufload(saved)
    vim.b[saved].straps_session = true
    vim.api.nvim_exec_autocmds('User', { pattern = 'StrapsRunStart', data = { bufnr = saved } })
    vim.wait(20, function() return false end)
    renamer.rename = original
    check(requests == 0, 'run-start event sends no automatic rename request')
    check(require('buff').state() == 'stopped', 'setup does not start Buff')
    local core = require('straps')
    check(core.config.context_management.enabled == true, 'context management enabled')
    check(core.config.context_management.mode == 'mechanical', 'mechanical mode selected')
    local management = require('straps.context_management')
    local prepared = { provider = 'openai', model = 'suite-fixture', body = { messages = {} },
      model_entry = { context_limit = 20000 }, output_reserve = 2000 }
    local budget = management.account(prepared, {})
    check(budget.limit == 13904, 'allowance subtracts output and suite retrieval reserves')
    check(budget.output_reserve == 2000, 'account preserves output reservation')
    local accepted, failure = pcall(management.account, { body = {} }, {})
    check(not accepted, 'account rejects missing allowance')
    check(tostring(failure):find('unknown input allowance', 1, true) ~= nil, 'missing allowance diagnostic')
    prepared.output_reserve = nil
    accepted, failure = pcall(management.account, prepared, {})
    check(not accepted, 'combined context requires output reservation')
    check(tostring(failure):find('explicit output reservation', 1, true) ~= nil, 'missing output reservation diagnostic')
    local state = require('straps.state')
    local buffer = vim.api.nvim_create_buf(false, true)
    state.append(buffer, 'system', nil, 'system instructions')
    state.append(buffer, 'user', nil, 'original user constraint')
    for i = 1, 4 do
      state.append(buffer, 'assistant', nil, 'assistant prose ' .. i)
      state.append(buffer, 'tool_use', { id = 't' .. i, name = 'read_file' }, '{"path":"fixture"}')
      state.append(buffer, 'tool_result', { id = 't' .. i }, 'evidence ' .. i .. string.rep('x', 9000))
    end
    state.append(buffer, 'user', nil, 'continue')
    vim.b[buffer].straps_context_management = { input_limit = 20000, trigger = 0.3, target = 0.9 }
    local provider = registry.get('fn.provider')
    registry.define({ name = 'fn.provider', kind = 'fn', source = "return function() error('offline fixture must not dispatch') end" })
    local before = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
    management.boundary(buffer, { bufnr = buffer, cancelled = function() return false end }, {}, {})
    registry.define(provider)
    local after = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
    local metrics = vim.b[buffer].straps_context_compaction
    check(metrics.status == 'applied', 'real mechanical boundary applies compaction')
    check(metrics.after.tokens < metrics.before.tokens, 'mechanical compaction reduces accounted input')
    check(#after < #before, 'mechanical compaction reduces transcript bytes')
    check(after:find('original user constraint', 1, true) ~= nil, 'mechanical compaction preserves user constraint')
    check(after:find('evidence 4' .. string.rep('x', 9000), 1, true) ~= nil, 'mechanical compaction retains latest evidence')
    local id = after:match('%[straps%-context:([%w_-]+)%]')
    check(id ~= nil, 'compaction inserts archive reference')
    local archived = require('straps.context_archive').get(buffer, id)
    check(archived and archived.sources[1].text:find('evidence 1', 1, true) ~= nil, 'archive stores replaced evidence')
  end, debug.traceback)
  vim.fn.delete(temporary, 'rf')
  if not ok then error(err, 0) end
  print('SUITE_ASSERTIONS=' .. count)
end

local ok, err = xpcall(mode and exercise or orchestrate, debug.traceback)
if not ok then
  io.stderr:write(tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
