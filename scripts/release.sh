#!/usr/bin/env bash
# Cuts a new semver release for the client, the backend, or both — tagging
# client-vX.Y.Z / api-vX.Y.Z respectively. Each tag triggers only its own
# CI workflow (client-artifacts.yml / backend-image.yml).
set -euo pipefail

bump="${1:-patch}"
if [[ ! "$bump" =~ ^(major|minor|patch)$ ]]; then
  echo "Usage: $0 [major|minor|patch]  (default: patch)" >&2
  exit 1
fi

root="$(dirname "$0")/.."
pubspec="$root/client/pubspec.yaml"
version_file="$root/backend/internal/httpapi/VERSION"

read -rp "Release [c]lient, [a]pi, or [b]oth? " target
release_client=0
release_api=0
case "$target" in
  c|client) release_client=1 ;;
  a|api) release_api=1 ;;
  b|both) release_client=1; release_api=1 ;;
  *) echo "Unknown option: $target" >&2; exit 1 ;;
esac

bump_semver() {
  local major minor patch
  IFS='.' read -r major minor patch <<< "$1"
  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  echo "${major}.${minor}.${patch}"
}

if [[ "$release_client" == 1 ]]; then
  client_current=$(grep '^version:' "$pubspec" | sed -E 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  client_next=$(bump_semver "$client_current")
  client_tag="client-v${client_next}"
  echo "Client:  ${client_current} -> ${client_next}  (${client_tag})"
fi

if [[ "$release_api" == 1 ]]; then
  api_current=$(tr -d '[:space:]' < "$version_file")
  api_next=$(bump_semver "$api_current")
  api_tag="api-v${api_next}"
  echo "Backend: ${api_current} -> ${api_next}  (${api_tag})"
fi

read -rp "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

if [[ "$release_client" == 1 ]]; then
  build_number=$(($(grep -o '+[0-9]*$' "$pubspec") + 1))
  perl -i -pe "s/^version: .*/version: ${client_next}+${build_number}/" "$pubspec"
  git -C "$root" add client/pubspec.yaml
  git -C "$root" commit -m "chore(client): bump version to ${client_next}+${build_number}"
fi

if [[ "$release_api" == 1 ]]; then
  echo "$api_next" > "$version_file"
  git -C "$root" add backend/internal/httpapi/VERSION
  git -C "$root" commit -m "chore(backend): bump version to ${api_next}"
fi

git -C "$root" push

if [[ "$release_client" == 1 ]]; then
  gh release create "$client_tag" --generate-notes
fi
if [[ "$release_api" == 1 ]]; then
  gh release create "$api_tag" --generate-notes
fi

echo "Done — GitHub Actions will build the artifacts for whatever was released."
