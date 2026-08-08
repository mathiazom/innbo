#!/usr/bin/env bash
# Cuts a new semver release by pushing a `vX.Y.Z` tag via `gh`, which
# triggers .github/workflows/backend-image.yml and client-artifacts.yml.
set -euo pipefail

bump="${1:-patch}"
if [[ ! "$bump" =~ ^(major|minor|patch)$ ]]; then
  echo "Usage: $0 [major|minor|patch]  (default: patch)" >&2
  exit 1
fi

latest=$(gh release list --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)
latest="${latest:-v0.0.0}"

IFS='.' read -r major minor patch <<< "${latest#v}"
case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac
next="v${major}.${minor}.${patch}"

echo "Latest release: ${latest}"
echo "Next release:   ${next}"
read -rp "Create and push ${next}? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

gh release create "$next" --generate-notes

echo "${next} pushed — GitHub Actions will build and attach the backend image + client artifacts."
