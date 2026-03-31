{
  pkgs,
  additionalPaths ? [ ],
  environment ? { },
  sourcesFile ? (
    let
      inherit (pkgs) lib;
      versionFiles = builtins.readDir ./versions;
      versionNames = builtins.map (f: lib.removeSuffix ".json" f) (
        builtins.filter (f: lib.hasSuffix ".json" f) (builtins.attrNames versionFiles)
      );
      latestVersion = builtins.head (builtins.sort (a: b: builtins.compareVersions a b > 0) versionNames);
    in
    ./versions/${latestVersion + ".json"}
  ),
  ...
}:
pkgs.callPackage ./package.nix (
  { inherit additionalPaths sourcesFile; }
  // pkgs.lib.optionalAttrs (environment != { }) { inherit environment; }
)
