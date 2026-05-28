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

      # The stable channel lags behind the latest release and cannot be derived
      # from the version file names, so update.ts records it in a `stable` marker.
      stableVersion = nixpkgs.lib.trim (builtins.readFile ./stable);
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
              additionalPaths = [ "${pkgs.gh}/bin" "${pkgs.poppler-utils}/bin" ];
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
          stableSourcesFile = ./versions/${stableVersion + ".json"};
        in
        {
          claude = mkClaude latestSourcesFile;
          claude-minimal = mkClaudeMinimal latestSourcesFile;
          latest = mkClaude latestSourcesFile;
          stable = mkClaude stableSourcesFile;
          stable-minimal = mkClaudeMinimal stableSourcesFile;
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
