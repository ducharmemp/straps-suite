local M = {}

function M.check()
  local health = vim.health
  health.start('straps-suite')
  local suite = require('straps_suite').status()
  if suite.failure then health.error(suite.failure) end
  if suite.configured then health.ok('Suite setup completed') else health.warn('Suite setup has not completed') end
  local cfg = suite.configuration or require('straps_suite.config').resolve()
  for _, item in ipairs(require('straps_suite.config').modules) do
    if cfg.extensions[item[1]] ~= false then
      if #vim.api.nvim_get_runtime_file('lua/' .. item[2] .. '/init.lua', false) > 0 then
        health.ok(item[1] .. ' is installed')
      else
        health.error(item[1] .. ' is missing')
      end
    end
  end
  for _, cmd in ipairs({ 'curl', 'rg', 'gzip' }) do
    if vim.fn.executable(cmd) == 1 then health.ok(cmd .. ' is available') else health.warn(cmd .. ' is missing') end
  end
  if cfg.extensions.classifier ~= false and suite.configured then
    require('straps_classifier.health').check()
  end
  health.start('straps-suite context management')
  if cfg.core.context_management.enabled then
    health.info('Mode: ' .. tostring(cfg.core.context_management.mode))
    if cfg.core.context_management.mode == 'summary' then
      health.warn('Summary mode makes provider requests and does not establish summary fidelity; Codex is unsupported')
    end
    if not cfg.core.context_management.input_limit and not cfg.core.context_management.context_limit then
      health.warn('Budget depends on active model metadata. Unknown input allowance blocks dispatch; configure input_limit for custom models')
    end
    if cfg.core.context_management.context_limit and not cfg.core.context_management.output_reserve then
      health.warn('Combined context requires an output reservation from the provider route or context_management.output_reserve')
    end
    health.info('Mechanical reduction can fail when preserved prose or protected evidence prevents reaching the target')
  else
    health.info('New context management is disabled; legacy thresholds are controlled by core settings')
  end
  if cfg.extensions.buff ~= false then
    health.start('straps-suite browser')
    local ok, api = pcall(require, 'buff.api')
    if ok and type(api.version) == 'function' and api.version() == 1 then health.ok('Buff API v1 available')
    else health.error('Compatible Buff API v1 is required') end
    local chrome = cfg.browser.chrome
    if chrome and vim.fn.executable(chrome) == 1 then health.ok('Configured Chromium executable is available')
    else health.info('Install Chromium or Chrome and configure browser.chrome if automatic discovery cannot find it') end
  end
end

return M
