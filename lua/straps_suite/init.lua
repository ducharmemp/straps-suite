local M = {}
local prepared, completed, failure
local specs = require('straps_suite.config')
local suppressed = false

local function configuration(opts)
  local cfg = specs.resolve(opts)
  assert(not prepared or vim.deep_equal(prepared, cfg), 'straps-suite: configuration changed; restart Neovim')
  assert(not failure, 'straps-suite: previous setup failed; restart Neovim: ' .. tostring(failure))
  return cfg
end

function M.prepare(opts)
  local cfg = configuration(opts)
  if prepared then return M end
  assert(not vim.g.loaded_straps_chartifier and not vim.g.loaded_straps_renamer,
    'straps-suite: prepare must run before chartifier and renamer plugin scripts; restart Neovim')
  vim.g.loaded_straps_chartifier = true
  vim.g.loaded_straps_renamer = true
  suppressed = true
  prepared = cfg
  return M
end

local function preflight(cfg)
  local registry = require('straps.registry')
  assert(registry.trusted_setup_allowed(), 'straps-suite: setup must precede sessions and guard freezing')
  local loaded = { core = require('straps') }
  for _, item in ipairs(specs.modules) do
    if cfg.extensions[item[1]] ~= false then
      loaded[item[1]] = require(item[2])
      assert(type(loaded[item[1]].setup) == 'function', 'straps-suite: missing setup in ' .. item[2])
    end
  end
  if cfg.extensions.buff ~= false then
    local api = require('buff.api')
    assert(type(api.version) == 'function' and api.version() == 1 and type(api.client) == 'function',
      'straps-suite: Buff API v1 is required')
    loaded.browser = require('buff')
  end
  if cfg.core.context_management.enabled then
    assert(type(require('straps.context_management').account) == 'function', 'straps-suite: core lacks context management')
  end
  return loaded
end

function M.setup(opts)
  local cfg = configuration(opts)
  if completed then return M end
  local loaded = preflight(cfg)
  if not prepared then M.prepare(opts) end
  local ok, err = pcall(function()
    loaded.core.setup(vim.deepcopy(cfg.core))
    if loaded.browser then loaded.browser.setup(vim.deepcopy(cfg.browser)) end
    for _, item in ipairs(specs.modules) do
      local name = item[1]
      if loaded[name] then
        loaded[name].setup(vim.deepcopy(cfg.extensions[name]))
        if name == 'classifier' then
          assert(loaded[name].installed, 'straps-suite: classifier installation failed: ' .. tostring(loaded[name].install_error))
        end
      end
    end
    require('straps_suite.keymaps').setup(cfg.keymaps)
    if cfg.attention then require('straps_suite.attention').setup() end
  end)
  if not ok then failure = tostring(err); error(err, 0) end
  completed = true
  return M
end

function M.status()
  return { prepared = prepared ~= nil, configured = completed == true, failure = failure,
    configuration = prepared and vim.deepcopy(prepared) or nil, suppressed = suppressed }
end

return M
