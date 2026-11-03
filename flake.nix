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
      systems = import ./systems.nix;
      forAllSystems = nixpkgs.lib.genAttrs systems;

      versionFiles = builtins.readDir ./versions;
      versionNames = builtins.map (f: nixpkgs.lib.removeSuffix ".json" f) (
        builtins.filter (f: nixpkgs.lib.hasSuffix ".json" f) (builtins.attrNames versionFiles)
      );

      latestVersion = builtins.head (builtins.sort (a: b: builtins.compareVersions a b > 0) versionNames);

      # The stable channel lags behind the latest release and cannot be derived
      # from the version file names, so update.nu records it in a `stable` marker.
      stableVersion = nixpkgs.lib.trim (builtins.readFile ./stable);

      latestSourcesFile = ./versions/${latestVersion + ".json"};
      stableSourcesFile = ./versions/${stableVersion + ".json"};

      mkClaude =
        pkgs: sourcesFile:
        pkgs.callPackage ./package.nix {
          additionalPaths = [
            "${pkgs.gh}/bin"
            "${pkgs.poppler-utils}/bin"
          ];
          inherit sourcesFile;
        };

      mkClaudeMinimal = pkgs: sourcesFile: pkgs.callPackage ./package.nix { inherit sourcesFile; };

      mkClaudeFhs =
        pkgs: claudePackage: pkgs.callPackage ./package-fhs.nix { claude-code = claudePackage; };
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

          versionedPackages = builtins.listToAttrs (
            builtins.map (version: {
              name = version;
              value = mkClaude pkgs ./versions/${version + ".json"};
            }) versionNames
          );

          fhsPackages = nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            claude-fhs = mkClaudeFhs pkgs (mkClaude pkgs latestSourcesFile);
            claude-minimal-fhs = mkClaudeFhs pkgs (mkClaudeMinimal pkgs latestSourcesFile);
            stable-fhs = mkClaudeFhs pkgs (mkClaude pkgs stableSourcesFile);
            stable-minimal-fhs = mkClaudeFhs pkgs (mkClaudeMinimal pkgs stableSourcesFile);
          };
        in
        {
          claude = mkClaude pkgs latestSourcesFile;
          claude-minimal = mkClaudeMinimal pkgs latestSourcesFile;
          latest = mkClaude pkgs latestSourcesFile;
          stable = mkClaude pkgs stableSourcesFile;
          stable-minimal = mkClaudeMinimal pkgs stableSourcesFile;
          default = self.packages.${system}.claude;
        }
        // fhsPackages
        // versionedPackages
      );

      # Build from the consumer's `final` rather than `self.packages`: the latter
      # instantiates this flake's own nixpkgs, which every overlay user would
      # then evaluate a second time. Unfree permission therefore comes from the
      # consumer's config, as the README already asks of overlay users.
      overlays.default =
        final: prev:
        let
          claude-code = mkClaude final latestSourcesFile;
          claude-code-minimal = mkClaudeMinimal final latestSourcesFile;
        in
        {
          inherit claude-code claude-code-minimal;
        }
        // nixpkgs.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
          claude-code-fhs = mkClaudeFhs final claude-code;
          claude-code-minimal-fhs = mkClaudeFhs final claude-code-minimal;
        };
    };
}
