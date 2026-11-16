# straps-suite

straps-suite configures Straps and seven extensions through one options table. It owns setup order, optional keymaps, and attention status. Configure the suite before opening a Straps session.

The default classifier sends every tool call to [TypeSafe](https://typesafe.ai) before the human approval dialog. A rejected call has still been disclosed. Without a working TypeSafe key, tool calls are denied. Review this disclosure before enabling the suite.

## Included plugins

| Extension key | Plugin | Purpose |
| --- | --- | --- |
| `divergent` | [straps-divergent](https://github.com/ducharmemp/straps-divergent) | Copy a conversation into a forked session |
| `exoskeleton` | [straps-exoskeleton](https://github.com/ducharmemp/straps-exoskeleton) | Shared org collaboration notebooks |
| `chartifier` | [straps-chartifier](https://github.com/ducharmemp/straps-chartifier) | Numeric charts |
| `buff` | [straps-buff](https://github.com/ducharmemp/straps-buff) | Buff browser tools |
| `kagi` | [straps-kagi](https://github.com/ducharmemp/straps-kagi) | Kagi search and page extraction |
| `renamer` | [straps-renamer](https://github.com/ducharmemp/straps-renamer) | Model-generated session titles |
| `classifier` | [straps-classifier](https://github.com/ducharmemp/straps-classifier) | Strict TypeSafe tool classification |

All extensions are enabled. Automatic renaming is disabled; `:StrapsRenameAuto` remains available and sends a transcript excerpt to the session's provider when invoked. Kagi requests disclose queries and URLs to Kagi and may incur charges. The classifier retains upstream strict defaults, with the suite's question cutoffs listed below. The suite adds no publishing bypass.

## Requirements

Use Neovim 0.11 or newer, curl, Straps provider credentials, and a TypeSafe key. Configure the latter through `TYPESAFE_API_KEY` or the classifier's supported key store. Kagi requires its own credentials; `:StrapsKagiLogin` stores them without putting a key in command arguments.

The browser extension requires Buff API v1 at revision `45ad0cb763138be7eeb03436bd34f0add7036257`. Install Chromium or Chrome separately with its sandbox enabled. Set `BUFF_CHROME` when Buff cannot locate the executable. The suite does not install a browser executable.

## Nixvim

Add the suite flake input, then import one module:

```nix
{
  inputs.straps-suite.url = "github:ducharmemp/straps-suite";
}
```

In the Nixvim configuration:

```nix
{
  imports = [ inputs.straps-suite.nixvimModules.default ];
  plugins.straps-suite = {
    enable = true;
    settings = {
      keymaps = "<leader>t";
      extensions.renamer.auto.enabled = false;
    };
  };
}
```

`plugins.straps-suite.enable` enables the suite. `settings` supplies the shared options table. `package` overrides the suite package. The module packages Straps, all seven extensions, and compatible Buff. It calls `prepare(settings)` through `extraConfigLuaPre`, then `setup(settings)` through `extraConfigLua`. Both calls run during editor initialization with dependency modules available; dependency plugin scripts run afterward.

Remove separate Straps, extension, and Buff setup configuration. Do not enable their individual Nixvim setup modules alongside the suite. Install Chromium through your system configuration if browser tools are enabled. The classifier flake input uses SSH; fetching it requires GitHub SSH access.

## lazy.nvim

Keep the options table local to the spec file and pass the same table to both phases:

```lua
local opts = {
  keymaps = '<leader>t',
  extensions = {
    renamer = { auto = { enabled = false } },
  },
}

return {
  'ducharmemp/straps-suite',
  lazy = false,
  dependencies = {
    'ducharmemp/straps',
    'ducharmemp/straps-divergent',
    'ducharmemp/straps-exoskeleton',
    'ducharmemp/straps-chartifier',
    { 'ducharmemp/buff.nvim', commit = '45ad0cb763138be7eeb03436bd34f0add7036257' },
    'ducharmemp/straps-buff',
    'ducharmemp/straps-kagi',
    'ducharmemp/straps-renamer',
    'ducharmemp/straps-classifier',
  },
  init = function(plugin)
    vim.opt.runtimepath:prepend(plugin.dir)
    require('straps_suite').prepare(opts)
  end,
  config = function()
    require('straps_suite').setup(opts)
  end,
}
```

Do not add `opts`, `config`, or separate setup calls to the dependencies. `init` must run before their plugin scripts. The suite's preparation suppresses the Chartifier and Renamer automatic plugin files so the suite can register them after core setup. Preparation rejects their already-loaded plugin flags; restart Neovim if either plugin ran first.

## Setup lifecycle

`require('straps_suite').prepare(opts)` resolves the options before dependency plugin scripts run. `require('straps_suite').setup(opts)` uses the same resolved options after dependencies load. With another plugin manager, reproduce those two phases. Calling only `setup()` after automatic dependency registration is too late.

Identical repeated calls are no-ops. Changed options after preparation or setup require a restart. A partial setup failure also requires a restart; setup does not roll back registration. An enabled dependency that is missing raises an error. Finish setup before opening any session so the classifier installs before Straps freezes its guards.

## Configuration

The suite accepts only these top-level keys:

| Key | Default | Effect |
| --- | --- | --- |
| `core` | Table below | Passed to `require('straps').setup()` |
| `extensions` | All seven enabled | Each short name accepts `false` or a settings table for that extension |
| `browser` | `{}` | Passed to `require('buff').setup()` |
| `keymaps` | `'<leader>t'` | Mapping prefix; `false` disables suite mappings |
| `attention` | `true` | Enables suite attention tracking |

Unknown suite keys and extension names are errors. The suite merges settings into its defaults. Use `extensions = { buff = false }` to skip browser tool registration; nonempty `browser` settings require the Buff extension. Each upstream extension processes its own settings, including warnings or errors for unsupported options.

An extension set to `false` skips suite setup; its dependency remains installed. Chartifier and Renamer automatic plugin scripts remain suppressed. Other upstream commands remain available, and collaboration commands can register Exoskeleton tools when invoked. These switches are configuration controls and do not revoke permission or remove installed packages.

The suite's core defaults are:

```lua
{
  max_spawn_depth = 4,
  compact_keep_turns = 2,
  context_management = {
    enabled = true,
    mode = 'mechanical',
    trigger = 0.85,
    target = 0.7,
    keep_turns = 2,
    reserve_tokens = 4096,
    minimum_savings = 128,
    idle_compaction = false,
  },
}
```

The suite adds these classifier settings to upstream strict defaults:

```lua
{
  max_state_bytes = 32000,
  ask_cutoffs = {
    viable = 0.6,
    disfavored = 0.6,
    steer_confidence = 0.6,
    asymmetric_detail = 0.7,
    decoy_present = 0.7,
    fairness = 2,
    marked_recommended = 0.7,
    deciding_factor = 0.5,
  },
}
```

These settings do not enable experimental contextual authorization. Missing credentials, classifier errors, and dangerous verdicts deny calls. The classifier can remove permission; it cannot grant it. See the classifier documentation before changing its policy.

## Context management

Mechanical mode archives eligible old tool results and leaves receipts for retrieval. It preserves user and assistant prose. Protected content can prevent reduction to the target; enabled context management does not guarantee that a request fits.

Dispatch requires a known model input allowance. Unknown model limits block dispatch. A combined `context_limit` requires an effective output reservation. For a custom provider or missing metadata, set `core.context_management.input_limit` to a reviewed allowance within the actual provider limit. An override cannot increase the provider's capacity. The request budget is an estimate and does not guarantee provider acceptance.

Summary mode is an explicit opt-in through `core.context_management.mode = 'summary'`. It makes additional provider requests and incurs tokens. It refuses the Codex route. Structural validation does not establish summary fidelity. Read `:help straps-context-management` before enabling it.

The legacy `auto_compact_tokens` and `auto_compact_bytes` thresholds remain unset. Disable the new context manager with:

```lua
local opts = {
  core = { context_management = { enabled = false } },
}
```

For an explicit legacy token threshold, choose a value from the selected model's reviewed budget:

```lua
local opts = {
  core = {
    context_management = { enabled = false },
    auto_compact_tokens = reviewed_token_threshold,
  },
}
```

`reviewed_token_threshold` is a value you must supply. No single threshold applies to every model. Pass the chosen options through both lifecycle phases.

## Keymaps and attention

Suite mappings preserve existing mappings. An installed which-key receives optional mapping descriptions; which-key is not required. Set `keymaps = false` to install no suite mappings, or choose another prefix.

All mappings use normal mode. Append these suffixes to the configured prefix:

| Suffix | Scope | Action |
| --- | --- | --- |
| `n` | Global | New session in a split |
| `v` | Global | New session in a vertical split |
| `t` | Global | New session in a tab |
| `r` | Global | Resume latest in a split |
| `V` | Global | Resume latest in a vertical split |
| `T` | Global | Resume latest in a tab |
| `R` | Global | Resume picker |
| `a` | Global | Agents buffer |
| `s` | Global | Enter transcript search |
| `m` | Global | Model picker |
| `e` | Global | Effort picker |
| `p` | Global | Provider picker |
| `x` | Straps buffer | Stop run |
| `c` | Straps buffer | Continue run |
| `g` | Straps buffer | Enter steering text |
| `k` | Straps buffer | Compact session |
| `N` | Straps buffer | Rename session |
| `u` | Straps buffer | Enter permission grants |

`require('straps_suite.attention').status()` returns text such as `2 working 1 waiting`, omits zero components, and returns an empty string when idle. `require('straps_suite.attention').counts()` returns `{ running = N, waiting = N }`. Counts cover top-level sessions. Waiting marks a completed run that has not been viewed while Neovim has focus. Cancelled runs do not add waiting attention. Viewing the session with focus clears its waiting state.

The suite reuses core `terminal_status` behavior rather than adding another terminal protocol. Set `core.terminal_status = false` to disable core terminal attention reports.

Zellij task-text integration and compatibility with old `StrapsZellij` globals are deferred. The suite defines no global status wrappers.

## Health and development

Run `:checkhealth straps_suite`, or call `require('straps_suite.health').check()`. Consult each extension's help for its tool contracts and credentials.

From the ecosystem root containing `straps-suite/`, use these verification commands:

```sh
nvim --headless -u NONE -l straps-suite/tests/run.lua
STRAPS_SUITE_ECO_ROOT=$PWD nvim --headless -u NONE -l straps-suite/tests/integration.lua
nix build --no-link --no-write-lock-file path:./straps-suite
nix flake check --no-write-lock-file path:./straps-suite
```

These commands describe verification; they do not record test outcomes.

## License

MIT. See [LICENSE](LICENSE).
