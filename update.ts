#!/usr/bin/env nix
/*
#! nix shell --inputs-from . nixpkgs#bun nixpkgs#oxfmt -c bun
*/

/**
 * Update script for claude package.
 *
 * Fetches the latest version from npm registry and retrieves
 * platform-specific binaries with checksums from manifest.json.
 *
 * Inspired by:
 * https://github.com/numtide/nix-ai-tools/blob/91132d4e72ed07374b9d4a718305e9282753bac9/packages/coderabbit-cli/update.py
 */

import { $, Glob, semver } from "bun";
import { join } from "node:path";

const BASE_URL =
  "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

// Type definitions
interface ManifestPlatform {
  checksum: string;
  size: number;
}

interface Manifest {
  version: string;
  buildDate: string;
  platforms: Record<string, ManifestPlatform>;
}

// Platform mappings (Nix platform -> manifest platform)
const platforms = {
  "x86_64-linux": "linux-x64",
  "aarch64-linux": "linux-arm64",
  "x86_64-darwin": "darwin-x64",
  "aarch64-darwin": "darwin-arm64",
} as const;

type NixPlatform = keyof typeof platforms;

/**
 * Fetch the latest version from npm registry.
 * The GCS stable endpoint may lag behind npm releases.
 */
async function fetchClaudeVersion(): Promise<string> {
  const url = "https://registry.npmjs.org/@anthropic-ai/claude-code/latest";
  const response = await fetch(url);
  const json = (await response.json()) as { version: string };
  return json.version;
}

/**
 * Fetch the manifest.json for a specific version.
 */
async function fetchManifest(version: string): Promise<Manifest> {
  const url = `${BASE_URL}/${version}/manifest.json`;
  const response = await fetch(url);
  const json = await response.json();
  return json as Manifest;
}

/**
 * Convert a SHA256 hex hash to SRI format.
 */
async function sha256ToSri(sha256Hex: string): Promise<string> {
  const result = await $`nix hash to-sri --type sha256 ${sha256Hex}`.text();
  return result.trim();
}

// Type definition for version sources
interface SourcesJSON {
  version: string;
  platforms: Record<NixPlatform, { url: string; hash: string }>;
}

/**
 * Get the current (latest) version from the versions directory.
 */
async function getCurrentVersion(): Promise<string | null> {
  const versionsDir = join(import.meta.dir, "versions");
  const glob = new Glob("*.json");
  const versions: string[] = [];
  for await (const f of glob.scan(versionsDir)) {
    versions.push(f.replace(/\.json$/, ""));
  }
  if (versions.length === 0) return null;
  versions.sort((a, b) => semver.order(a, b));
  return versions[versions.length - 1];
}

/**
 * Write version sources to the versions directory.
 */
async function writeVersionSources(
  version: string,
  hashes: Record<NixPlatform, string>,
): Promise<void> {
  const versionedPath = join(import.meta.dir, "versions", `${version}.json`);

  const platformsData: Record<NixPlatform, { url: string; hash: string }> =
    {} as any;

  for (const [nixPlatform, manifestPlatform] of Object.entries(platforms)) {
    const url = `${BASE_URL}/${version}/${manifestPlatform}/claude`;
    platformsData[nixPlatform as NixPlatform] = {
      url,
      hash: hashes[nixPlatform as NixPlatform],
    };
  }

  const sourcesData: SourcesJSON = {
    version,
    platforms: platformsData,
  };

  await Bun.write(versionedPath, JSON.stringify(sourcesData, null, 2) + "\n");
}

// Main execution
const currentVersion = await getCurrentVersion();
const latestVersion = await fetchClaudeVersion();

console.log(`Current version: ${currentVersion}`);
console.log(`Latest version: ${latestVersion}`);

console.log(`Updating claude from ${currentVersion} to ${latestVersion}`);

// Fetch manifest and extract hashes
console.log("Fetching manifest.json...");
const manifest = await fetchManifest(latestVersion);
const hashes: Record<NixPlatform, string> = {} as Record<NixPlatform, string>;

for (const [nixPlatform, manifestPlatform] of Object.entries(platforms)) {
  const checksum = manifest.platforms[manifestPlatform].checksum;
  const sriHash = await sha256ToSri(checksum);
  hashes[nixPlatform as NixPlatform] = sriHash;
  console.log(`  ${nixPlatform}: ${sriHash}`);
}

console.log();

// Write versioned sources file
await writeVersionSources(latestVersion, hashes);
console.log(`Updated claude to version ${latestVersion}`);

// Format with oxfmt
console.log("Formatting with oxfmt...");
await $`oxfmt --config ${join(import.meta.dir, ".oxfmtrc.jsonc")} versions/*.json`.quiet();
console.log("Done!");
