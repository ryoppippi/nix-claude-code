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

# GCS (Google Cloud Storage) distribution endpoint
const BASE_URL = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

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

# Fetch a version string from a GCS distribution channel (`latest` or `stable`).
def fetch-gcs-channel [channel: string] {
	http get $"($BASE_URL)/($channel)" | str trim
}

# Get all existing versions from the versions directory.
def get-existing-versions [] {
	let names = (
		glob ($script_dir | path join "versions" "*.json")
		| each { path parse | get stem }
	)
	match ($names | is-empty) {
		true => {versions: [], latest: null}
		false => {
			let sorted = ($names | semver-sort)
			{versions: $sorted, latest: ($sorted | last)}
		}
	}
}

# Write version sources to the versions directory.
def write-version-sources [version: string, hashes: record] {
	let versioned_path = ($script_dir | path join "versions" $"($version).json")

	let platforms_data = (
		$platforms
		| items {|nix_platform, manifest_platform|
			{$nix_platform: {
				url: $"($BASE_URL)/($version)/($manifest_platform)/claude"
				hash: ($hashes | get $nix_platform)
			}}
		}
		| reduce -f {} {|it, acc| $acc | merge $it}
	)

	let sources_data = {version: $version, platforms: $platforms_data}
	(($sources_data | to json --indent 2) + "\n") | save -f $versioned_path
}

# Fetch manifest, compute SRI hashes, and write the version file.
# Returns true if the version was written, false if the manifest was unavailable.
def process-version [version: string] {
	let manifest = (try { http get $"($BASE_URL)/($version)/manifest.json" } catch {|err|
		print -e $"  Skipping ($version): ($err.msg)"
		null
	})

	match $manifest {
		null => false
		_ => {
			let results = (
				$platforms
				| items {|nix_platform, manifest_platform|
					let platform_data = ($manifest.platforms | get -o $manifest_platform)
					match $platform_data {
						null => {
							print -e $"  Skipping ($version): missing platform ($manifest_platform)"
							null
						}
						_ => {$nix_platform: (nix hash to-sri --type sha256 $platform_data.checksum | str trim)}
					}
				}
			)

			match ($results | any {|r| $r == null}) {
				true => false
				false => {
					let hashes = ($results | reduce -f {} {|it, acc| $acc | merge $it})
					write-version-sources $version $hashes
					true
				}
			}
		}
	}
}

# Backfill every version file missing from the tracked range, refresh the
# `stable` channel marker, and print the newest known version as the final line
# for CI consumption.
def main [] {
	let existing = (get-existing-versions)
	let existing_versions = $existing.versions
	let current_version = $existing.latest

	let all_npm_versions = (http get $NPM_PACKAGE_URL | get versions | columns | semver-sort)
	let npm_latest = (http get $NPM_LATEST_URL | get version)
	# The stable channel intentionally lags behind the latest release.
	let gcs_latest = (fetch-gcs-channel "latest")
	let stable_version = (fetch-gcs-channel "stable")

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

	match ($missing_versions | is-empty) {
		true => { print "All versions are up to date!" }
		false => {
			print $"Found ($missing_versions | length) missing version\(s\): ($missing_versions | str join ', ')"

			$missing_versions | each {|version|
				print $"Processing ($version)..."
				match (process-version $version) {
					true => { print $"  Added ($version)" }
					false => {}
				}
			} | ignore
		}
	}

	# Ensure the stable version is tracked before recording the channel marker.
	# The marker must never point at a version file that does not exist, or the
	# flake's `stable` alias would fail to evaluate — on failure keep the previous
	# marker (still valid, stable naturally lags) and retry on the next run.
	let stable_path = ($script_dir | path join "versions" $"($stable_version).json")
	match ($stable_path | path exists) {
		true => {}
		false => {
			print $"Processing stable ($stable_version)..."
			process-version $stable_version | ignore
		}
	}
	match ($stable_path | path exists) {
		true => {
			# The flake reads this marker to expose the `stable` package alias.
			# The `latest` channel needs no marker: the flake derives it from
			# the highest version file name.
			$"($stable_version)\n" | save -f ($script_dir | path join "stable")
			print $"Marked stable -> ($stable_version)"
		}
		false => {
			print -e $"Keeping previous stable marker: failed to process stable ($stable_version)"
		}
	}

	# Format with oxfmt
	print "Formatting with oxfmt..."
	cd $script_dir
	oxfmt --config ($script_dir | path join ".oxfmtrc.jsonc") versions/*.json | ignore
	print "Done!"

	# Print the latest version as the final line for CI consumption
	print $latest_version
}
