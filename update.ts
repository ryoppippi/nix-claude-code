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

import { $, Glob, semver } from 'bun';
import { join } from 'node:path';

const BASE_URL =
	'https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases';

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
	'x86_64-linux': 'linux-x64',
	'aarch64-linux': 'linux-arm64',
	'x86_64-darwin': 'darwin-x64',
	'aarch64-darwin': 'darwin-arm64',
} as const;

type NixPlatform = keyof typeof platforms;

/**
 * Fetch the latest version from npm registry.
 * The GCS stable endpoint may lag behind npm releases.
 */
async function fetchClaudeVersion(): Promise<string> {
	const url = 'https://registry.npmjs.org/@anthropic-ai/claude-code/latest';
	const response = await fetch(url);
	const json = (await response.json()) as { version: string };
	return json.version;
}

/**
 * Fetch all published versions from npm registry.
 * @returns Sorted array of all version strings.
 */
async function fetchAllVersions(): Promise<string[]> {
	const url = 'https://registry.npmjs.org/@anthropic-ai/claude-code';
	const response = await fetch(url);
	const json = (await response.json()) as { versions: Record<string, unknown> };
	const versions = Object.keys(json.versions);
	versions.sort((a, b) => semver.order(a, b));
	return versions;
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
 * Get all existing versions from the versions directory.
 * @returns Object with the sorted set of existing versions and the latest one.
 */
async function getExistingVersions(): Promise<{
	versions: Set<string>;
	latest: string | null;
}> {
	const versionsDir = join(import.meta.dir, 'versions');
	const glob = new Glob('*.json');
	const versions: string[] = [];
	for await (const f of glob.scan(versionsDir)) {
		versions.push(f.replace(/\.json$/, ''));
	}
	if (versions.length === 0) return { versions: new Set(), latest: null };
	versions.sort((a, b) => semver.order(a, b));
	return { versions: new Set(versions), latest: versions[versions.length - 1] };
}

/**
 * Write version sources to the versions directory.
 */
async function writeVersionSources(
	version: string,
	hashes: Record<NixPlatform, string>,
): Promise<void> {
	const versionedPath = join(import.meta.dir, 'versions', `${version}.json`);

	const platformsData: Record<NixPlatform, { url: string; hash: string }> = {} as any;

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

	await Bun.write(versionedPath, JSON.stringify(sourcesData, null, 2) + '\n');
}

/**
 * Fetch manifest, compute SRI hashes, and write the version file.
 * @returns true if the version was written, false if the manifest was unavailable.
 */
async function processVersion(version: string): Promise<boolean> {
	let manifest: Manifest;
	try {
		manifest = await fetchManifest(version);
	} catch {
		console.warn(`  Skipping ${version}: manifest not available`);
		return false;
	}

	const hashes: Record<NixPlatform, string> = {} as Record<NixPlatform, string>;

	for (const [nixPlatform, manifestPlatform] of Object.entries(platforms)) {
		const platformData = manifest.platforms[manifestPlatform];
		if (!platformData) {
			console.warn(`  Skipping ${version}: missing platform ${manifestPlatform}`);
			return false;
		}
		const sriHash = await sha256ToSri(platformData.checksum);
		hashes[nixPlatform as NixPlatform] = sriHash;
	}

	await writeVersionSources(version, hashes);
	return true;
}

// Main execution
const { versions: existingVersions, latest: currentVersion } = await getExistingVersions();
const allNpmVersions = await fetchAllVersions();
const latestVersion = allNpmVersions[allNpmVersions.length - 1];

console.log(`Current version: ${currentVersion}`);
console.log(`Latest version:  ${latestVersion}`);

// Find the earliest existing version to determine the backfill range.
// Only backfill versions >= the earliest version we already track.
const existingArray = [...existingVersions].sort((a, b) => semver.order(a, b));
const earliest = existingArray[0];

const missingVersions = allNpmVersions.filter(
	(v) => !existingVersions.has(v) && (!earliest || semver.order(v, earliest) >= 0),
);

if (missingVersions.length === 0) {
	console.log('All versions are up to date!');
} else {
	console.log(`Found ${missingVersions.length} missing version(s): ${missingVersions.join(', ')}`);

	for (const version of missingVersions) {
		console.log(`Processing ${version}...`);
		const ok = await processVersion(version);
		if (ok) {
			console.log(`  Added ${version}`);
		}
	}
}

// Format with oxfmt
console.log('Formatting with oxfmt...');
await $`oxfmt --config ${join(import.meta.dir, '.oxfmtrc.jsonc')} versions/*.json`.quiet();
console.log('Done!');

// Print the latest version as the final line for CI consumption
console.log(latestVersion);
