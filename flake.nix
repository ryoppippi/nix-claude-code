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

          mkClaudeFhs = claudePackage: pkgs.callPackage ./package-fhs.nix { claude-code = claudePackage; };

          versionedPackages = builtins.listToAttrs (
            builtins.map (version: {
              name = version;
              value = mkClaude ./versions/${version + ".json"};
            }) versionNames
          );

          latestSourcesFile = ./versions/${latestVersion + ".json"};

          fhsPackages = nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            claude-fhs = mkClaudeFhs (mkClaude latestSourcesFile);
            claude-minimal-fhs = mkClaudeFhs (mkClaudeMinimal latestSourcesFile);
          };
        in
        {
          claude = mkClaude latestSourcesFile;
          claude-minimal = mkClaudeMinimal latestSourcesFile;
          default = self.packages.${system}.claude;
        }
        // fhsPackages
        // versionedPackages
      );

      overlays.default =
        _final: prev:
        {
          claude-code = self.packages.${prev.stdenv.hostPlatform.system}.claude;
          claude-code-minimal = self.packages.${prev.stdenv.hostPlatform.system}.claude-minimal;
        }
        // nixpkgs.lib.optionalAttrs prev.stdenv.isLinux {
          claude-code-fhs = self.packages.${prev.stdenv.hostPlatform.system}.claude-fhs;
          claude-code-minimal-fhs = self.packages.${prev.stdenv.hostPlatform.system}.claude-minimal-fhs;
        };
    };
}
