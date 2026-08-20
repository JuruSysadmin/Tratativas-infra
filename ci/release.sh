#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${RELEASE_TAG:-}" ]]; then
  tag="${RELEASE_TAG#refs/tags/}"
else
  mapfile -t tags < <(git tag --points-at HEAD 'v*' | sort)
  if (( ${#tags[@]} != 1 )); then
    printf 'expected exactly one v<semver> tag at HEAD, found %s\n' "${#tags[@]}" >&2
    exit 1
  fi
  tag="${tags[0]}"
fi

tag_commit=$(git rev-parse "refs/tags/$tag^{commit}" 2>/dev/null || true)
head_commit=$(git rev-parse HEAD)
if [[ -z "$tag_commit" || "$tag_commit" != "$head_commit" ]]; then
  printf 'release tag %s must exist and point to HEAD\n' "$tag" >&2
  exit 1
fi

project_version=$(python3 - "$tag" <<'PY'
import re
import sys
from pathlib import Path

tag = sys.argv[1]
version = tag.removeprefix("v")
semver_pattern = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

if not tag.startswith("v") or semver_pattern.fullmatch(version) is None:
    raise SystemExit(f"invalid release tag: {tag}")

text = Path("mix.exs").read_text()
match = re.search(r'version:\s*"([^"]+)"', text)
if match is None:
    raise SystemExit("version not found in mix.exs")
project_version = match.group(1)
if version != project_version:
    raise SystemExit(
        f"tag version {version} does not match mix.exs version {project_version}"
    )

print(version)
PY
)
version="$project_version"

export MIX_ENV=prod
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
mix assets.setup
mix assets.build
mix release chat

mkdir -p artifacts
tarball="artifacts/chat-${version}.tar.gz"
tar -czf "$tarball" -C _build/prod/rel chat
sha256sum "$tarball" > "${tarball}.sha256"
printf 'release=%s\nchecksum=%s\n' "$tarball" "${tarball}.sha256"
