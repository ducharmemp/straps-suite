{ pkgs, module, package, nixvim, invert ? 0 }:
let
  inherit (pkgs) lib;
  evaluate = extra: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ({ lib, ... }: {
        options = {
          extraPlugins = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
          extraPackages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
          extraConfigLuaPre = lib.mkOption { type = lib.types.lines; default = ""; };
          extraConfigLua = lib.mkOption { type = lib.types.lines; default = ""; };
        };
      })
      module
      extra
    ];
  }).config;
  enabled = evaluate { plugins.straps-suite.enable = true; };
  disabled = evaluate { };
  custom = pkgs.vimUtils.buildVimPlugin { pname = "straps-suite-override"; version = "test"; src = package.src; };
  overridden = evaluate {
    plugins.straps-suite = { enable = true; package = custom; settings.core.model = "test-model"; };
    extraConfigLuaPre = "suite_pre_marker = true";
    extraConfigLua = "suite_setup_marker = true";
  };
  checks = [
    (enabled.extraPlugins == [ package ])
    (enabled.extraPackages == [ pkgs.curl pkgs.ripgrep pkgs.gzip ])
    (disabled.extraPlugins == [ ] && disabled.extraPackages == [ ])
    (disabled.extraConfigLuaPre == "" && disabled.extraConfigLua == "")
    (lib.hasInfix ''require("straps_suite").prepare'' enabled.extraConfigLuaPre)
    (lib.hasInfix ''require("straps_suite").setup'' enabled.extraConfigLua)
    (!(lib.hasInfix ".setup" enabled.extraConfigLuaPre) && !(lib.hasInfix ".prepare" enabled.extraConfigLua))
    (lib.hasInfix "test-model" overridden.extraConfigLuaPre && lib.hasInfix "test-model" overridden.extraConfigLua)
    (lib.hasPrefix ''require("straps_suite").prepare'' overridden.extraConfigLuaPre)
    (lib.hasSuffix "suite_pre_marker = true" overridden.extraConfigLuaPre)
    (lib.hasPrefix "suite_setup_marker = true" overridden.extraConfigLua)
    (lib.hasSuffix "})\n" overridden.extraConfigLua)
    (overridden.extraPlugins == [ custom ])
    (builtins.length package.dependencies == 9)
    (!(enabled.plugins ? straps) && !(enabled.plugins ? buff))
  ];
  makeStartup = mode: nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system}.makeNixvim {
    imports = [ module ];
    nixpkgs.pkgs = pkgs;
    plugins.straps-suite = {
      enable = true;
      settings = lib.optionalAttrs (mode == "disabled") { extensions = { chartifier = false; renamer = false; }; };
    };
    extraConfigLuaPre = lib.mkAfter ''
      vim.g.suite_prepared_before_dependencies = require('straps_suite').status().prepared
        and not vim.g.loaded_straps and vim.fn.exists(':BuffStart') == 0
    '';
    extraConfigLuaPost = ''
      vim.g.suite_configured_before_dependencies = require('straps_suite').status().configured
        and not vim.g.loaded_straps and vim.fn.exists(':BuffStart') == 0
    '' + builtins.readFile ./lazy.lua;
  };
  startups = map (mode: { inherit mode; package = makeStartup mode; }) [ "defaults" "disabled" ];
in
assert lib.assertMsg (builtins.all (value: value) (lib.imap1 (index: value: if index == invert then !value else value) checks))
  ("straps-suite module evaluation predicates: " + builtins.toJSON checks + "; inversion=" + toString invert);
pkgs.runCommand "straps-suite-nixvim" { nativeBuildInputs = [ pkgs.neovim pkgs.curl pkgs.ripgrep pkgs.gzip ]; } ''
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
  ${lib.concatMapStringsSep "\n" (startup: ''
    STRAPS_SUITE_STARTUP_NVIM=${startup.package}/bin/nvim STRAPS_SUITE_STARTUP_MODE=${startup.mode} \
      nvim --headless -u NONE -l ${./lazy.lua}
  '') startups}
  touch "$out"
''
