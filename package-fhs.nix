{
  lib,
  buildFHSEnv,
  claude-code,
}:
# Wrap claude-code in an FHS-compatible environment so that binaries
# downloaded at runtime (e.g. by the agent-teams feature) can find
# the standard dynamic linker at /lib64/ld-linux-x86-64.so.2.
# See: https://github.com/ryoppippi/claude-code-overlay/issues/16
buildFHSEnv {
  name = "claude";
  inherit (claude-code) meta;

  targetPkgs = pkgs: [
    claude-code
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];

  runScript = lib.getExe claude-code;
}
