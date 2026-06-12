# nix-claude-code

A Nix flake that provides pre-built Claude Code CLI binaries from official Anthropic releases.

This flake downloads binaries directly from Anthropic's distribution servers.

## Getting Started

```bash
# Run the latest version
nix run github:ryoppippi/nix-claude-code

# Run the stable channel
nix run 'github:ryoppippi/nix-claude-code#stable'

# Run a specific version
nix run 'github:ryoppippi/nix-claude-code#"2.1.81"'
```

## Features

- ✅ Automatic updates via GitHub Actions (hourly checks)
- ✅ Multi-platform support: Linux (x86_64, aarch64) and macOS (x86_64, aarch64)
- ✅ Direct downloads from official Anthropic servers
- ✅ SHA256 checksum verification
- ✅ Flake and non-flake support
- ✅ Binary cache via [Cachix](https://app.cachix.org/cache/ryoppippi) for faster builds

## Why Use This Flake?

While there are existing Claude Code packages in the Nix ecosystem ([llm-agents.nix](https://github.com/numtide/llm-agents.nix) and [nixpkgs](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/cl/claude-code/package.nix)), this flake provides the **official pre-built binary distribution** with several advantages:

### Official Support

- **Recommended by Anthropic**: Anthropic has deprecated the npm (JavaScript) distribution and now recommends the pre-built native binary distribution that this flake packages
- **Direct from official distribution**: Binaries downloaded directly from Anthropic's servers
- **Guaranteed compatibility**: Official builds are tested and verified by Anthropic

### Additional Benefits

- **Faster updates**: Automated hourly checks ensure you get the latest version quickly
- **Consistent behaviour**: Same binaries used across all platforms match official installation methods
- **Simplified maintenance**: No need to rebuild from source or manage runtime dependencies

## Unfree Licence Notice

Claude Code is distributed under an unfree licence. You must explicitly allow unfree packages to use this flake.

### Option 1: Per-Package Allowance (Recommended)

The safest approach - only allows Claude Code specifically:

**For NixOS** (`configuration.nix`):

```nix
nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "claude"
];
```

**For home-manager** (`home.nix`):

```nix
nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "claude"
];
```

**For standalone config** (`~/.config/nixpkgs/config.nix`):

```nix
{
  allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude"
  ];
}
```

### Option 2: Global Allow (Not Recommended)

Only use if you understand the implications:

```nix
nixpkgs.config.allowUnfree = true;
```

This permits **all** unfree packages system-wide without explicit review.

## Binary Cache (Cachix)

This flake provides pre-built binaries via [Cachix](https://app.cachix.org/cache/ryoppippi). Using the binary cache avoids rebuilding packages locally and significantly speeds up installation.

### Setup Cachix

**Option 1: Using Cachix CLI**

```bash
cachix use ryoppippi
```

**Option 2: Manual Configuration**

Add to your Nix configuration:

```nix
# NixOS (configuration.nix)
nix.settings = {
  substituters = [ "https://ryoppippi.cachix.org" ];
  trusted-public-keys = [ "ryoppippi.cachix.org-1:b2LbtWNvJeL/qb1B6TYOMK+apaCps4SCbzlPRfSQIms=" ];
};

# Or in ~/.config/nix/nix.conf
# extra-substituters = https://ryoppippi.cachix.org
# extra-trusted-public-keys = ryoppippi.cachix.org-1:b2LbtWNvJeL/qb1B6TYOMK+apaCps4SCbzlPRfSQIms=
```

**Option 3: In your flake.nix (for flake consumers)**

```nix
{
  nixConfig = {
    extra-substituters = [ "https://ryoppippi.cachix.org" ];
    extra-trusted-public-keys = [ "ryoppippi.cachix.org-1:b2LbtWNvJeL/qb1B6TYOMK+apaCps4SCbzlPRfSQIms=" ];
  };

  # ... rest of your flake
}
```

**Option 4: Using devenv**

```nix
{
  cachix.pull = [ "ryoppippi" ];
}
```

## Usage

### Quick Start

Try Claude Code without installation:

```bash
# Run Claude Code directly
nix run github:ryoppippi/nix-claude-code

# Or enter a shell with Claude Code available
nix shell github:ryoppippi/nix-claude-code
claude --version
```

### With Flakes

#### Simple usage

Add the overlay to your flake inputs:

```nix
{
  inputs = {
    nix-claude-code.url = "github:ryoppippi/nix-claude-code";
  };
}
```

Then use `pkgs.claude-code` in your configuration after adding the overlay to your `pkgs`.

#### Add to NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude-code.url = "github:ryoppippi/nix-claude-code";
  };

  outputs = { nixpkgs, nix-claude-code, ... }: {
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, lib, ... }: {
          nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude" ];
          nixpkgs.overlays = [ nix-claude-code.overlays.default ];
          environment.systemPackages = [ pkgs.claude-code ];
        })
      ];
    };
  };
}
```

#### Add to devShell

Use Claude Code in a project-specific development environment.

**Method 1: Direct package reference (Recommended)**

The simplest approach - no `allowUnfree` configuration required:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude-code.url = "github:ryoppippi/nix-claude-code";
  };

  outputs = { nixpkgs, nix-claude-code, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              nix-claude-code.packages.${system}.default
              # Add other development tools here
            ];
          };
        }
      );
    };
}
```

**Method 2: Using overlay**

Use this if you want to reference the package as `pkgs.claude-code`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude-code.url = "github:ryoppippi/nix-claude-code";
  };

  outputs = { nixpkgs, nix-claude-code, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude" ];
            overlays = [ nix-claude-code.overlays.default ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.claude-code
              # Add other development tools here
            ];
          };
        }
      );
    };
}
```

Then run:

```bash
nix develop
claude --version
```

#### Add to devenv

Use Claude Code in a [devenv](https://devenv.sh/) development environment.

**Add the input using CLI:**

```bash
devenv inputs add nix-claude-code github:ryoppippi/nix-claude-code
```

**Or manually in devenv.yaml:**

```yaml
inputs:
  nix-claude-code:
    url: github:ryoppippi/nix-claude-code
```

**devenv.nix:**

```nix
{ pkgs, inputs, ... }:
{
  packages = [
    inputs.nix-claude-code.packages.${pkgs.system}.default
  ];

  # Optional: use Cachix for faster builds
  cachix.pull = [ "ryoppippi" ];
}
```

Then run:

```bash
devenv shell
claude --version
```

#### Add to home-manager

Use the overlay with home-manager's built-in `programs.claude-code` module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-claude-code.url = "github:ryoppippi/nix-claude-code";
  };

  outputs = { nixpkgs, home-manager, nix-claude-code, ... }: {
    homeConfigurations."user@hostname" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude" ];
        overlays = [ nix-claude-code.overlays.default ];
      };
      modules = [{
        programs.claude-code = {
          enable = true;
          package = pkgs.claude-code;
        };
      }];
    };
  };
}
```

### Without Flakes

```nix
let
  nix-claude-code = import (builtins.fetchTarball {
    url = "https://github.com/ryoppippi/nix-claude-code/archive/main.tar.gz";
  });
  pkgs = import <nixpkgs> {
    config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "claude" ];
    overlays = [ nix-claude-code.overlays.default ];
  };
in
  pkgs.claude-code
```

## Available Packages

The flake provides two package variants (exposed via the overlay):

| Package                    | Description                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `pkgs.claude-code`         | Default package with GitHub CLI (`gh`) bundled. Recommended for most users as Claude Code frequently uses `gh` for GitHub operations. |
| `pkgs.claude-code-minimal` | Minimal package without bundled tools. Use this if you want to provide your own `gh` version or don't need GitHub integration.        |

### Release Channels

In addition to per-version attributes, the flake exposes channel aliases that track Anthropic's release channels. The `latest` channel follows the newest release (cross-checked against both the npm registry and Anthropic's distribution server), while `stable` follows the slower-moving stable channel, which intentionally lags behind `latest`.

| Attribute                           | Channel                                       |
| ----------------------------------- | --------------------------------------------- |
| `packages.${system}.default`        | Latest release (same as `latest`)             |
| `packages.${system}.latest`         | Latest release, with `gh` bundled             |
| `packages.${system}.stable`         | Stable channel release, with `gh` bundled     |
| `packages.${system}.stable-minimal` | Stable channel release, without bundled tools |

```bash
# Latest release
nix run github:ryoppippi/nix-claude-code#latest

# Stable channel
nix run github:ryoppippi/nix-claude-code#stable
```

### FHS-Wrapped Variants (Linux only)

Claude Code's `agent-teams` feature downloads an additional Linux binary at runtime to `~/.local/share/claude`. That binary is unpatched and expects the standard FHS dynamic linker at `/lib64/ld-linux-x86-64.so.2`, which does not exist on NixOS. The flake exposes FHS-wrapped variants that provide a glibc-based root so these runtime-downloaded binaries can execute.

| Attribute                                | Description                            |
| ---------------------------------------- | -------------------------------------- |
| `packages.${system}.claude-fhs`          | FHS-wrapped `claude` (latest)          |
| `packages.${system}.claude-minimal-fhs`  | FHS-wrapped `claude-minimal` (latest)  |
| `packages.${system}.stable-fhs`          | FHS-wrapped `stable`                   |
| `packages.${system}.stable-minimal-fhs`  | FHS-wrapped `stable-minimal`           |
| `pkgs.claude-code-fhs` (overlay)         | Overlay alias for `claude-fhs`         |
| `pkgs.claude-code-minimal-fhs` (overlay) | Overlay alias for `claude-minimal-fhs` |

The default `claude` / `claude-code` packages are unchanged — the FHS variants are opt-in because `buildFHSEnv` relies on user namespaces (`bwrap`), which are unavailable in some environments (e.g. some CI runners, restricted containers).

### Telemetry

By default, this package does **not** disable telemetry or nonessential network traffic. This is intentional — disabling them breaks features like remote-control that depend on these subsystems.

If you want to disable telemetry (at the cost of breaking remote-control and potentially other features), use the `disableTelemetry` override:

```nix
claude-code.override { disableTelemetry = true; }
```

Or set the environment variables yourself:

```bash
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
```

#### What's always disabled

The wrapper always sets these regardless of the `disableTelemetry` option:

| Variable                              | Purpose                                                             |
| ------------------------------------- | ------------------------------------------------------------------- |
| `DISABLE_AUTOUPDATER=1`               | Nix handles updates, auto-updater is unnecessary                    |
| `DISABLE_INSTALLATION_CHECKS=1`       | Suppresses installation method warnings                             |
| `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1` | Suppresses chatty flavour text from the model (overridable via env) |

#### Links

- [Claude Code](https://claude.ai/code)
- [Changelog](https://github.com/anthropics/claude-code/releases)
- [Issue: telemetry breaks remote-control](https://github.com/anthropics/claude-code/issues/15592)

### Version Pinning

You can install a specific version of Claude Code by using versioned package attributes:

```nix
# Use a specific version
nix-claude-code.packages.${system}."2.1.81"

# Always use the latest (default behaviour)
nix-claude-code.packages.${system}.default

# Follow the latest channel explicitly
nix-claude-code.packages.${system}.latest

# Follow the stable channel
nix-claude-code.packages.${system}.stable
```

```bash
# Run a specific version directly
nix run 'github:ryoppippi/nix-claude-code#"2.1.81"'
```

All versions that have been tracked by this repository are available. See the [`versions/`](./versions) directory for available versions.

### Using claude-code-minimal with custom tools

If you want to use your own version of `gh` or add other tools to the PATH, use `claude-code-minimal` with `additionalPaths`:

```nix
# In your configuration
pkgs.claude-code-minimal.override {
  additionalPaths = [ "${pkgs.gh}/bin" "${pkgs.git}/bin" ];
}
```

## How It Works

1. The `update.nu` script determines the newest release by checking both the npm registry and Anthropic's distribution server, and also records the current `stable` channel version
2. It retrieves official SHA256 checksums from manifest.json and converts them to SRI format, writing one source file per version under `versions/` plus a `stable` channel marker
3. GitHub Actions runs the update script hourly and commits any changes
4. The flake provides pre-built binaries compiled with Bun for all supported platforms

## Supported Platforms

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin` (macOS Intel)
- `aarch64-darwin` (macOS Apple Silicon)

## Development

Development tooling (formatters, linters, git hooks) is separated into `dev/flake.nix` to keep the main flake minimal for consumers. This means your `flake.lock` will only contain essential dependencies (`nixpkgs`, `flake-utils`), not development tools like `treefmt-nix` or `git-hooks`.

### Setup development environment

**Option 1: Using direnv (Recommended)**

If you have [direnv](https://direnv.net/) installed:

```bash
direnv allow
```

This automatically loads the development environment and installs pre-commit hooks when you enter the directory.

**Option 2: Manual**

Enter the development shell:

```bash
nix develop ./dev
```

This automatically installs git pre-commit hooks that run:

- **nixfmt-rfc-style** - Nix code formatter (RFC 166)
- **deadnix** - Dead code detection
- **statix** - Nix linter

### Update sources manually

```bash
nix develop ./dev
./update
```

### Test the build

```bash
nix build
./result/bin/claude --version
```

### Run checks manually

```bash
# Format all Nix files
nix fmt ./dev

# Run all checks (formatting, linting)
nix flake check ./dev
```

## Related Projects

- [llm-agents.nix](https://github.com/numtide/llm-agents.nix) - Nix flake providing various AI/LLM tools including Claude Code
- [nixpkgs claude-code](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/cl/claude-code/package.nix) - Official nixpkgs package for Claude Code

### Comparison with llm-agents.nix

Both this flake and llm-agents.nix provide Claude Code packages using the official pre-built binaries. The main differences are:

| Feature              | nix-claude-code  | llm-agents.nix   |
| -------------------- | ---------------- | ---------------- |
| **Scope**            | Claude Code only | 50+ AI/LLM tools |
| **Update frequency** | Hourly           | Daily            |

Choose **nix-claude-code** if you want faster updates. For other AI/LLM tools (Gemini CLI, OpenCode, etc.), we recommend using **llm-agents.nix**. Both can be used together.

## Credits

- Claude Code CLI by [Anthropic](https://anthropic.com)

## Licence

MIT
