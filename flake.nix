{
  description = "Claude Code CLI binaries.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "claude"
              ];
          };
        in
        {
          claude = pkgs.callPackage ./default.nix {
            additionalPaths = [ "${pkgs.gh}/bin" ];
          };
          claude-minimal = pkgs.callPackage ./default.nix { };
          default = self.packages.${system}.claude;
        }
      );

      overlays.default = _final: prev: {
        claude-code = self.packages.${prev.stdenv.hostPlatform.system}.claude;
        claude-code-minimal = self.packages.${prev.stdenv.hostPlatform.system}.claude-minimal;
      };
    };
}
