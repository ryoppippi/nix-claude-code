{
  description = "Development environment for nix-claude-code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        let
          # Shared by the gitleaks flake check (full `detect`) and the
          # commit-time pre-commit hook (`protect --staged`), so both stages
          # honour the same rules.
          gitleaksConfig = ./../.gitleaks.toml;
        in
        {
          treefmt = {
            # Format-check the whole repository, not just `dev/`, so the
            # `treefmt` flake check covers every tracked file. `cleanSource`
            # strips `.git`, so anchor the project root on `flake.nix`.
            projectRoot = pkgs.lib.cleanSource ./..;
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
              typos.enable = true;
              oxfmt.enable = true;
            };
          };

          # Expose a full gitleaks scan as a flake check so `nix flake check`
          # covers secret detection. The flake sandbox has no `.git`, so we scan
          # the cleaned working tree with `--no-git` rather than the git history.
          checks.gitleaks =
            pkgs.runCommand "gitleaks"
              {
                nativeBuildInputs = [ pkgs.gitleaks ];
              }
              ''
                gitleaks detect \
                  --source ${pkgs.lib.cleanSource ./..} \
                  --config ${gitleaksConfig} \
                  --no-git \
                  --redact
                touch "$out"
              '';

          pre-commit = {
            # These hooks run on `git commit` via the dev shell. `nix flake
            # check` covers the same ground through the dedicated `treefmt` and
            # `gitleaks` checks, so disable the pre-commit flake check to avoid
            # running gitleaks and treefmt twice.
            check.enable = false;
            settings = {
              src = ./..;
              package = pkgs.prek;
              hooks = {
                treefmt = {
                  enable = true;
                  package = config.treefmt.build.wrapper;
                };
                renovate-config-validator = {
                  enable = true;
                  entry = "${pkgs.lib.getExe' pkgs.renovate "renovate-config-validator"}";
                  files = "renovate\\.json5?$";
                  language = "system";
                };
                gitleaks = {
                  enable = true;
                  name = "gitleaks";
                  entry = "${pkgs.lib.getExe pkgs.gitleaks} protect --staged --config ${gitleaksConfig}";
                  language = "system";
                  pass_filenames = false;
                };
              };
            };
          };

          packages = {
            inherit (pkgs) typos typos-lsp;
          };

          devShells.default = pkgs.mkShellNoCC {
            inherit (config.pre-commit) shellHook;
            packages = [
              config.packages.typos
              config.packages.typos-lsp
              pkgs.gitleaks
            ];
          };
        };
    };
}
