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
    inputs@{
      flake-parts,
      git-hooks,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          pkgs,
          self',
          system,
          ...
        }:
        let
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = ".git/config";
            programs = {
              nixfmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
              typos.enable = true;
              oxfmt.enable = true;
            };
          };
        in
        {
          checks = {
            git-hooks-check = git-hooks.lib.${system}.run {
              src = ./..;
              hooks = {
                treefmt = {
                  enable = true;
                  package = treefmtEval.config.build.wrapper;
                };
                renovate-config-validator = {
                  enable = true;
                  entry = "${pkgs.renovate}/bin/renovate-config-validator";
                  files = "renovate\\.json5?$";
                  language = "system";
                };
              };
              package = pkgs.prek;
            };
          };

          formatter = treefmtEval.config.build.wrapper;

          packages = {
            inherit (pkgs) typos typos-lsp;
          };

          devShells.default = pkgs.mkShellNoCC {
            inherit (self'.checks.git-hooks-check) shellHook;
            packages = [
              self'.packages.typos
              self'.packages.typos-lsp
            ];
          };
        };
    };
}
