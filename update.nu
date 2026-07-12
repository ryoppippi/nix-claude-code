#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell nixpkgs#oxfmt -c nu

# Update script for claude package.
#
# Fetches the latest version from npm registry and retrieves
# platform-specific binaries with checksums from manifest.json.
#
# Inspired by:
# https://github.com/numtide/nix-ai-tools/blob/91132d4e72ed07374b9d4a718305e9282753bac9/packages/coderabbit-cli/update.py

const script_dir = (path self .)

# GCS (Google Cloud Storage) distribution endpoints
const BASE_URL = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
const GCS_LATEST_URL = $"($BASE_URL)/latest"
const GCS_STABLE_URL = $"($BASE_URL)/stable"

# npm registry endpoints
const NPM_PACKAGE_URL = "https://registry.npmjs.org/@anthropic-ai/claude-code"
const NPM_LATEST_URL = $"($NPM_PACKAGE_URL)/latest"

# Platform mappings (Nix platform -> manifest platform)
const platforms = {
	"x86_64-linux": "linux-x64"
	"aarch64-linux": "linux-arm64"
	"x86_64-darwin": "darwin-x64"
	"aarch64-darwin": "darwin-arm64"
}

# Sort a list of version strings using semver ordering (ascending).
def semver-sort []: list<string> -> list<string> {
	$in | each { into semver } | sort | each { into string }
}

# Check whether version `a` is greater than or equal to version `b`.
# Semver values support sort but not comparison operators, so the check
# sorts the pair and tests whether `a` comes out on top. Both sides are
# normalised through `into semver | into string` so a non-canonical input
# string cannot break the equality test.
def semver-gte [a: string, b: string] {
	let last_sorted = ([$b $a] | each { into semver } | sort | last | into string)
	$last_sorted == ($a | into semver | into string)
}

# Fetch the latest version from the npm registry.
def fetch-npm-latest-version [] {
	http get $NPM_LATEST_URL | get version
}

# Fetch the latest version from the GCS distribution endpoint.
def fetch-gcs-latest-version [] {
	http get $GCS_LATEST_URL | str trim
}

# Fetch the stable version from the GCS distribution endpoint.
# The stable channel intentionally lags behind the latest release.
def fetch-gcs-stable-version [] {
	http get $GCS_STABLE_URL | str trim
}

# Fetch all published versions from npm registry, sorted ascending.
def fetch-all-versions [] {
	http get $NPM_PACKAGE_URL | get versions | columns | semver-sort
}

# Fetch the manifest.json for a specific version.
def fetch-manifest [version: string] {
	http get $"($BASE_URL)/($version)/manifest.json"
}

# Convert a SHA256 hex hash to SRI format.
def sha256-to-sri [sha256_hex: string] {
	(nix hash to-sri --type sha256 $sha256_hex | str trim)
}

# Get all existing versions from the versions directory.
def get-existing-versions [] {
	let names = (
		glob ($script_dir | path join "versions" "*.json")
		| each { path parse | get stem }
	)
	if ($names | is-empty) {
		{versions: [], latest: null}
	} else {
		let sorted = ($names | semver-sort)
		{versions: $sorted, latest: ($sorted | last)}
	}
}

# Write version sources to the versions directory.
def write-version-sources [version: string, hashes: record] {
	let versioned_path = ($script_dir | path join "versions" $"($version).json")

	mut platforms_data = {}
	for it in ($platforms | transpose nix_platform manifest_platform) {
		let url = $"($BASE_URL)/($version)/($it.manifest_platform)/claude"
		$platforms_data = ($platforms_data | insert $it.nix_platform {
			url: $url
			hash: ($hashes | get $it.nix_platform)
		})
	}

	let sources_data = {version: $version, platforms: $platforms_data}
	(($sources_data | to json --indent 2) + "\n") | save -f $versioned_path
}

# Write the `stable` channel marker file containing a version string.
# The flake reads this marker to expose the `stable` package alias. The
# `latest` channel needs no marker: the flake derives it from the highest
# version file name.
def write-stable-marker [version: string] {
	let marker_path = ($script_dir | path join "stable")
	$"($version)\n" | save -f $marker_path
}

# Fetch manifest, compute SRI hashes, and write the version file.
# Returns true if the version was written, false if the manifest was unavailable.
def process-version [version: string] {
	let manifest = (try { fetch-manifest $version } catch {|err|
		print -e $"  Skipping ($version): ($err.msg)"
		null
	})
	if $manifest == null {
		return false
	}

	mut hashes = {}
	for it in ($platforms | transpose nix_platform manifest_platform) {
		let platform_data = ($manifest.platforms | get -o $it.manifest_platform)
		if $platform_data == null {
			print -e $"  Skipping ($version): missing platform ($it.manifest_platform)"
			return false
		}
		$hashes = ($hashes | insert $it.nix_platform (sha256-to-sri $platform_data.checksum))
	}

	write-version-sources $version $hashes
	true
}

# Main execution
let existing = (get-existing-versions)
let existing_versions = $existing.versions
let current_version = $existing.latest

let all_npm_versions = (fetch-all-versions)
let npm_latest = (fetch-npm-latest-version)
let gcs_latest = (fetch-gcs-latest-version)
let stable_version = (fetch-gcs-stable-version)

# Determine the newest version reported by either source.
let latest_version = ([$npm_latest $gcs_latest] | semver-sort | last)

print $"Current version: ($current_version)"
print $"npm latest:      ($npm_latest)"
print $"GCS latest:      ($gcs_latest)"
print $"GCS stable:      ($stable_version)"
print $"Latest version:  ($latest_version)"

# Find the earliest existing version to determine the backfill range.
# Only backfill versions >= the earliest version we already track.
let earliest = ($existing_versions | get 0?)

let missing_versions = (
	$all_npm_versions
	| where {|v| $v not-in $existing_versions and ($earliest == null or (semver-gte $v $earliest))}
)

if ($missing_versions | is-empty) {
	print "All versions are up to date!"
} else {
	print $"Found ($missing_versions | length) missing version\(s\): ($missing_versions | str join ', ')"

	for version in $missing_versions {
		print $"Processing ($version)..."
		let ok = (process-version $version)
		if $ok {
			print $"  Added ($version)"
		}
	}
}

# Ensure the stable version is tracked before recording the channel marker.
# The marker must never point at a version file that does not exist, or the
# flake's `stable` alias would fail to evaluate — on failure keep the previous
# marker (still valid, stable naturally lags) and retry on the next run.
let stable_path = ($script_dir | path join "versions" $"($stable_version).json")
if not ($stable_path | path exists) {
	print $"Processing stable ($stable_version)..."
	process-version $stable_version | ignore
}
if ($stable_path | path exists) {
	write-stable-marker $stable_version
	print $"Marked stable -> ($stable_version)"
} else {
	print -e $"Keeping previous stable marker: failed to process stable ($stable_version)"
}

# Format with oxfmt
print "Formatting with oxfmt..."
cd $script_dir
oxfmt --config ($script_dir | path join ".oxfmtrc.jsonc") versions/*.json | ignore
print "Done!"

# Print the latest version as the final line for CI consumption
print $latest_version
