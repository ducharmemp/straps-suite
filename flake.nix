{
  description = "Coordinated setup for the Straps plugin suite";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
    nixvim.url = "github:nix-community/nixvim/453dc9c5037e6d1bec81d2a51ddacd58a2f44e9c";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    lazy = { url = "github:folke/lazy.nvim/306a05526ada86a7b30af95c5cc81ffba93fef97"; flake = false; };
    straps = { url = "github:ducharmemp/straps/c16e7d31ddafac8446b339b35b50e2de1e5fdffb"; flake = false; };
    straps-buff = { url = "github:ducharmemp/straps-buff/7351631448cbd547ae6a7e2cbb87240e901c8207"; flake = false; };
    straps-chartifier = { url = "github:ducharmemp/straps-chartifier/dc9d8f34ac504f9df7e712df298002970741db90"; flake = false; };
    straps-classifier = { url = "github:ducharmemp/straps-classifier/277043fe45ed5ea4e8790a7495b0476ccd42bbc6"; flake = false; };
    straps-divergent = { url = "github:ducharmemp/straps-divergent/5cce48ab7cb726f097d81112ecfbcc0cc5133162"; flake = false; };
    straps-exoskeleton = { url = "github:ducharmemp/straps-exoskeleton/734b67d3ac70757b34728558c0f5be065bce7db3"; flake = false; };
    straps-kagi = { url = "github:ducharmemp/straps-kagi/53c0ef4afcb93eb2dd1b64d92c29024f6bc333fa"; flake = false; };
    straps-renamer = { url = "github:ducharmemp/straps-renamer/b7b5ffcef1a4ace9ea7464ba81e33cd563bdcd21"; flake = false; };
    buff = { url = "github:ducharmemp/buff.nvim/45ad0cb763138be7eeb03436bd34f0add7036257"; flake = false; };
  };

  outputs = inputs@{ self, nixpkgs, straps, ... }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      names = [ "straps" "straps-buff" "straps-chartifier" "straps-classifier" "straps-divergent" "straps-exoskeleton" "straps-kagi" "straps-renamer" "buff" ];
      sources = lib.genAttrs names (name: toString inputs.${name});
      sourceJSON = builtins.toJSON sources;
      core = (import "${straps}/flake.nix").outputs { self = straps // core; inherit nixpkgs; };
      mkDependencies = pkgs:
        let
          corePlugin = core.packages.${pkgs.stdenv.hostPlatform.system}.default;
          buffPlugin = pkgs.vimUtils.buildVimPlugin {
            pname = "buff-nvim";
            version = inputs.buff.shortRev or "pinned";
            src = inputs.buff;
          };
          extensions = map (name: pkgs.vimUtils.buildVimPlugin {
            pname = name;
            version = inputs.${name}.shortRev or "pinned";
            src = inputs.${name};
            dependencies = [ corePlugin buffPlugin ];
          }) (lib.remove "straps" (lib.remove "buff" names));
        in [ corePlugin buffPlugin ] ++ extensions;
      mkSuite = pkgs: pkgs.vimUtils.buildVimPlugin {
        pname = "straps-suite";
        version = "dev";
        src = self;
        dependencies = mkDependencies pkgs;
        meta.license = lib.licenses.mit;
      };
      suiteModule = { config, lib, pkgs, ... }:
        let
          cfg = config.plugins.straps-suite;
          settings = lib.generators.toLua { } cfg.settings;
        in {
          options.plugins.straps-suite = {
            enable = lib.mkEnableOption "the coordinated Straps plugin suite";
            package = lib.mkOption {
              type = lib.types.package;
              default = mkSuite pkgs;
              description = "The suite plugin package, including its plugin dependencies.";
            };
            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "Options passed to straps_suite.prepare and straps_suite.setup. Chromium remains user-managed.";
            };
          };
          config = lib.mkIf cfg.enable {
            extraPlugins = [ cfg.package ];
            extraPackages = [ pkgs.curl pkgs.ripgrep pkgs.gzip ];
            extraConfigLuaPre = lib.mkBefore ''
              require("straps_suite").prepare(${settings})
            '';
            extraConfigLua = lib.mkAfter ''
              require("straps_suite").setup(${settings})
            '';
          };
        };
      mkTest = pkgs: name: script: pkgs.runCommand "straps-suite-${name}" {
        nativeBuildInputs = [ pkgs.neovim pkgs.curl pkgs.ripgrep pkgs.gzip ];
        STRAPS_SUITE_SOURCES = sourceJSON;
        STRAPS_SUITE_LAZY = inputs.lazy;
      } ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
        export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
        mkdir -p "$HOME"
        cd ${self}
        nvim --headless -u NONE -l ${script}
        touch "$out"
      '';
      mkTrynix = pkgs: pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
        plugins = [ (mkSuite pkgs) ];
        waylandSupport = false;
        luaRcContent = ''require("straps_suite").prepare({}) require("straps_suite").setup({})'';
        wrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ pkgs.curl pkgs.ripgrep pkgs.gzip ]) ];
      };
    in {
      packages = forAllSystems (pkgs: rec {
        straps-suite = mkSuite pkgs;
        trynix = mkTrynix pkgs;
        default = straps-suite;
      });
      nixvimModules = { default = suiteModule; straps-suite = suiteModule; };
      checks = forAllSystems (pkgs: {
        unit = mkTest pkgs "unit" "tests/run.lua";
        integration = mkTest pkgs "integration" "tests/integration.lua";
        lazy = mkTest pkgs "lazy" "tests/lazy.lua";
        nixvim = import ./tests/nixvim.nix { inherit pkgs; inherit (inputs) nixvim; module = suiteModule; package = mkSuite pkgs; };
      });
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.neovim pkgs.curl pkgs.ripgrep pkgs.gzip ];
          STRAPS_SUITE_SOURCES = sourceJSON;
        };
      });
    };
}
