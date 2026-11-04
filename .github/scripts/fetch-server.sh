#!/usr/bin/env bash
# Downloads the latest Paper build for $MC_VERSION and the latest packetevents release for it
# into the given server directory.
set -euo pipefail

dir="${1:?usage: fetch-server.sh <server-dir>}"
: "${MC_VERSION:?MC_VERSION must be set}"
ua="${USER_AGENT:-paperaccurate263-ci}"
mkdir -p "$dir/plugins"

fetch() { curl -fsSL --retry 3 -H "User-Agent: $ua" "$@"; }

# --- Paper (fill v3 API) ---
if ! build_json=$(fetch "https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds/latest"); then
  echo "builds/latest failed, falling back to the build list"
  build_json=$(fetch "https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds" | jq 'max_by(.id)')
fi
paper_url=$(jq -r '.downloads."server:default".url' <<<"$build_json")
paper_sha=$(jq -r '.downloads."server:default".checksums.sha256' <<<"$build_json")
echo "Paper ${MC_VERSION} build $(jq -r '.id' <<<"$build_json") ($(jq -r '.channel' <<<"$build_json")): $paper_url"
fetch -o "$dir/paper.jar" "$paper_url"
echo "$paper_sha  $dir/paper.jar" | sha256sum -c -

# --- packetevents (Modrinth) ---
pe_json=$(fetch -G "https://api.modrinth.com/v2/project/packetevents/version" \
  --data-urlencode 'loaders=["paper"]' \
  --data-urlencode "game_versions=[\"${MC_VERSION}\"]")
if [ "$(jq 'length' <<<"$pe_json")" -eq 0 ]; then
  echo "no packetevents release on Modrinth for ${MC_VERSION}" >&2
  exit 1
fi
pe_version=$(jq -r '.[0].version_number' <<<"$pe_json")
pe_url=$(jq -r '.[0].files | (map(select(.primary)) + .)[0].url' <<<"$pe_json")
pe_sha=$(jq -r '.[0].files | (map(select(.primary)) + .)[0].hashes.sha512' <<<"$pe_json")
echo "packetevents ${pe_version}: $pe_url"
fetch -o "$dir/plugins/packetevents.jar" "$pe_url"
echo "$pe_sha  $dir/plugins/packetevents.jar" | sha512sum -c -

ls -la "$dir" "$dir/plugins"
