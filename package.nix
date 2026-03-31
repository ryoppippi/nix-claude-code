{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  zlib,
  additionalPaths ? [ ],
  environment ? {
    DISABLE_AUTOUPDATER = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
  },
  sourcesFile,
}:
let
  sourcesData = lib.importJSON sourcesFile;
  inherit (sourcesData) version;
  sources = sourcesData.platforms;

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  pathPrefix = lib.optionalString (additionalPaths != [ ])
    "--prefix PATH : ${builtins.concatStringsSep ":" additionalPaths}";

  envFlags = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg value}") environment
  );
in
stdenv.mkDerivation rec {
  pname = "claude";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/claude

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/claude ${pathPrefix} ${envFlags}
  '';

  dontStrip = true; # to not mess with the bun runtime

  doInstallCheck = true;

  # Workaround: Custom version check using strings command instead of running the binary
  # The standard versionCheckHook fails with "TypeError: failed to initialize Segmenter" in Nix sandbox.
  # This workaround extracts version string from the binary without executing it.
  # Note: This is not a documented nixpkgs pattern, but a practical workaround for this specific issue.
  # See: https://github.com/ryoppippi/nix-claude-code/issues/5
  installCheckPhase =
    let
      inherit (lib) pipe escapeRegex escapeShellArg;
      escapedVersion = pipe version [
        escapeRegex
        escapeShellArg
      ];
    in
    ''
      runHook preInstallCheck

      if strings $out/bin/claude | grep -q ${escapedVersion}; then
        echo "Found version ${version} in binary"
      else
        echo "ERROR: Version ${version} not found in binary"
        exit 1
      fi

      runHook postInstallCheck
    '';

  passthru = {
    updateScript = ./update.ts;
  };

  meta = with lib; {
    inherit version;
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://claude.ai/code";
    downloadPage = "https://github.com/anthropics/claude-code/releases";
    changelog = "https://github.com/anthropics/claude-code/releases";
    license = licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "claude";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    maintainers = [ ];
  };
}
