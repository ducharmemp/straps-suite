local M = {}

M.modules = {
  { 'divergent', 'straps-divergent' },
  { 'exoskeleton', 'straps_collab' },
  { 'chartifier', 'straps_chartifier' },
  { 'buff', 'straps-buff' },
  { 'kagi', 'straps_kagi' },
  { 'renamer', 'straps_renamer' },
  { 'classifier', 'straps_classifier' },
}

function M.resolve(opts)
  assert(opts == nil or type(opts) == 'table', 'straps-suite: options must be a table')
  opts = opts or {}
  local allowed = { core = true, extensions = true, browser = true, keymaps = true, attention = true }
  for key in pairs(opts) do assert(allowed[key], 'straps-suite: unknown option ' .. tostring(key)) end
  for _, key in ipairs({ 'core', 'extensions', 'browser' }) do
    assert(opts[key] == nil or type(opts[key]) == 'table', 'straps-suite: ' .. key .. ' must be a table')
  end
  assert(opts.attention == nil or type(opts.attention) == 'boolean', 'straps-suite: attention must be boolean')
  assert(opts.keymaps == nil or opts.keymaps == false or type(opts.keymaps) == 'string' and opts.keymaps ~= '',
    'straps-suite: keymaps must be false or a nonempty prefix')
  local cfg = {
    core = { max_spawn_depth = 2, compact_keep_turns = 2,
      context_management = { enabled = true, mode = 'mechanical', trigger = 0.85, target = 0.7, keep_turns = 2,
        reserve_tokens = 4096, minimum_savings = 128, idle_compaction = false } },
    extensions = { divergent = {}, exoskeleton = {}, chartifier = {}, buff = {}, kagi = {},
      renamer = { auto = { enabled = false } },
      classifier = { max_state_bytes = 32000, ask_cutoffs = { viable = 0.6, disfavored = 0.6, steer_confidence = 0.6,
        asymmetric_detail = 0.7, decoy_present = 0.7, fairness = 2, marked_recommended = 0.7, deciding_factor = 0.5 } } },
    browser = {}, keymaps = '<leader>t', attention = true,
  }
  for key, value in pairs(opts.extensions or {}) do
    assert(cfg.extensions[key] ~= nil, 'straps-suite: unknown extension ' .. tostring(key))
    assert(value == false or type(value) == 'table', 'straps-suite: extension ' .. key .. ' must be false or a table')
  end
  cfg = vim.tbl_deep_extend('force', cfg, vim.deepcopy(opts))
  assert(cfg.extensions.buff ~= false or next(cfg.browser) == nil, 'straps-suite: browser settings require the Buff extension')
  return cfg
end

return M
