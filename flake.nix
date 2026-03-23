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

      versionFiles = builtins.readDir ./versions;
      versionNames = builtins.map (f: nixpkgs.lib.removeSuffix ".json" f) (
        builtins.filter (f: nixpkgs.lib.hasSuffix ".json" f) (builtins.attrNames versionFiles)
      );
      latestVersion = builtins.head (builtins.sort (a: b: builtins.compareVersions a b > 0) versionNames);
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

          mkClaude =
            sourcesFile:
            pkgs.callPackage ./package.nix {
              additionalPaths = [ "${pkgs.gh}/bin" ];
              inherit sourcesFile;
            };

          mkClaudeMinimal = sourcesFile: pkgs.callPackage ./package.nix { inherit sourcesFile; };

          versionedPackages = builtins.listToAttrs (
            builtins.map (version: {
              name = version;
              value = mkClaude ./versions/${version + ".json"};
            }) versionNames
          );

          latestSourcesFile = ./versions/${latestVersion + ".json"};
        in
        {
          claude = mkClaude latestSourcesFile;
          claude-minimal = mkClaudeMinimal latestSourcesFile;
          default = self.packages.${system}.claude;
        }
        // versionedPackages
      );

      overlays.default = _final: prev: {
        claude-code = self.packages.${prev.stdenv.hostPlatform.system}.claude;
        claude-code-minimal = self.packages.${prev.stdenv.hostPlatform.system}.claude-minimal;
      };
    };
}
