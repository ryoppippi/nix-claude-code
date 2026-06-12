#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell nixpkgs#oxfmt -c nu
# Update script for claude package.
#
# Fetches the latest version from npm registry and retrieves
# platform-specific binaries with checksums from manifest.json.
#
# Inspired by:
# https://github.com/numtide/nix-ai-tools/blob/91132d4e72ed07374b9d4a718305e9282753bac9/packages/coderabbit-cli/update.py
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
# Build a lexicographically-comparable sort key from a semver string.
#
# Each dot-separated component is reduced to its leading run of digits and
# zero-padded to a fixed width, so plain string comparison (`<`, `>=`) and
# `sort-by` order versions numerically rather than lexically (e.g. `2.1.20`
# sorts after `2.1.9`). Non-numeric components (pre-release tags) fall back to
# their numeric prefix, or `0` when none is present.
def version-key [v: string]: nothing -> string {
    $v | split row "." | each { |p|
		$p
		| parse --regex '^(?<n>\d+)'
		| get n.0?
		| default "0"
		| into int
		| fill --alignment right --character "0" --width 12
	} | str join "."
}
# Sort a list of version strings in ascending semver order.
def sort-versions [versions: list<string>]: nothing -> list<string> {
    $versions | sort-by {|v| version-key $v }
}
# Fetch the latest version from the npm registry.
def fetch-npm-latest-version []: nothing -> string {
    http get $NPM_LATEST_URL | get version
}
# Fetch the latest version from the GCS distribution endpoint.
def fetch-gcs-latest-version []: nothing -> string {
    http get --raw $GCS_LATEST_URL | str trim
}
# Fetch the stable version from the GCS distribution endpoint.
# The stable channel intentionally lags behind the latest release.
def fetch-gcs-stable-version []: nothing -> string {
    http get --raw $GCS_STABLE_URL | str trim
}
# Fetch all published versions from npm registry, sorted ascending.
def fetch-all-versions []: nothing -> list<string> {
    let versions = http get $NPM_PACKAGE_URL | get versions | columns
    sort-versions $versions
}
# Fetch the manifest.json for a specific version, or null when unavailable.
def fetch-manifest [version: string]: nothing -> any {
    let url = $"($BASE_URL)/($version)/manifest.json"
    try { http get $url } catch { null }
}
# Convert a SHA256 hex hash to SRI format.
def sha256-to-sri [sha256_hex: string]: nothing -> string {
    ^nix hash to-sri --type sha256 $sha256_hex | str trim
}
# Get all existing versions from the versions directory.
# Returns a record with the sorted list of existing versions and the latest one.
def get-existing-versions []: nothing -> record {
    let versions_dir = $env.FILE_PWD | path join "versions"
    let versions = (glob ($versions_dir | path join "*.json") | each {|f| $f | path basename | str replace --regex '\.json$' "" })
    if ($versions | is-empty) {
        return {
            versions: []
            latest: null
        }
    }
    let sorted = (sort-versions $versions)
    {
        versions: $sorted
        latest: ($sorted | last)
    }
}
# Write version sources to the versions directory.
def write-version-sources [version: string, hashes: record]: nothing -> nothing {
    let versioned_path = $env.FILE_PWD | path join "versions" $"($version).json"
    mut platforms_data = {}
    for entry in ($platforms | transpose nix manifest) {
        let url = $"($BASE_URL)/($version)/($entry.manifest)/claude"
        $platforms_data = ($platforms_data | insert $entry.nix { url: $url, hash: ($hashes | get $entry.nix) })
    }
    let sources_data = {
        version: $version
        platforms: $platforms_data
    }
    $"($sources_data | to json --indent 2)\n" | save --force $versioned_path
}
# Write the `stable` channel marker file containing a version string.
# The flake reads this marker to expose the `stable` package alias. The
# `latest` channel needs no marker: the flake derives it from the highest
# version file name.
def write-stable-marker [version: string]: nothing -> nothing {
    let marker_path = $env.FILE_PWD | path join "stable"
    $"($version)\n" | save --force $marker_path
}
# Fetch manifest, compute SRI hashes, and write the version file.
# Returns true if the version was written, false if the manifest was unavailable.
def process-version [version: string]: nothing -> bool {
    let manifest = (fetch-manifest $version)
    if $manifest == null {
        print $"  Skipping ($version): manifest not available"
        return false
    }
    mut hashes = {}
    for entry in ($platforms | transpose nix manifest) {
        let platform_data = $manifest.platforms | get $entry.manifest --optional
        if $platform_data == null {
            print $"  Skipping ($version): missing platform ($entry.manifest)"
            return false
        }
        $hashes = ($hashes | insert $entry.nix (sha256-to-sri $platform_data.checksum))
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
let latest_version = sort-versions [$npm_latest, $gcs_latest] | last
print $"Current version: ($current_version)"
print $"npm latest:      ($npm_latest)"
print $"GCS latest:      ($gcs_latest)"
print $"GCS stable:      ($stable_version)"
print $"Latest version:  ($latest_version)"
# Find the earliest existing version to determine the backfill range.
# Only backfill versions >= the earliest version we already track.
let earliest = $existing_versions | first
let existing_set = $existing_versions | reduce --fold {} {|it, acc| $acc | insert $it true }
let missing_versions = ($all_npm_versions | where { |v|
		(not ($v in $existing_set)) and (($earliest == null) or ((version-key $v) >= (version-key $earliest)))
	})
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
# Ensure the stable version is tracked, then record the channel markers.
if (not ($stable_version in $existing_set)) and (not ($stable_version in $missing_versions)) {
    print $"Processing stable ($stable_version)..."
    process-version $stable_version | ignore
}
write-stable-marker $stable_version
print $"Marked stable -> ($stable_version)"
# Format with oxfmt
print "Formatting with oxfmt..."
^oxfmt --config ($env.FILE_PWD | path join ".oxfmtrc.jsonc") ...(glob ($env.FILE_PWD | path join "versions" "*.json")) | ignore
print "Done!"
# Print the latest version as the final line for CI consumption
print $latest_version
