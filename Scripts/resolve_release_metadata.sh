#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--shell]" >&2
}

OUTPUT_MODE="plain"
if [[ $# -gt 0 ]]; then
  case "$1" in
    --shell)
      OUTPUT_MODE="shell"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

if [[ $# -ne 0 ]]; then
  usage
  exit 2
fi

fail() {
  echo "error: $*" >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "run from inside a git repository"

exact_tags=()
while IFS= read -r tag; do
  exact_tags+=("${tag}")
done < <(git tag --points-at HEAD | LC_ALL=C sort)
if [[ ${#exact_tags[@]} -eq 0 ]]; then
  fail "HEAD must be exactly on a release tag matching vX.Y.Z"
fi

valid_tags=()
for tag in "${exact_tags[@]}"; do
  if [[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    valid_tags+=("${tag}")
  fi
done

if [[ ${#valid_tags[@]} -eq 0 ]]; then
  fail "HEAD exact tag must match vX.Y.Z; found: ${exact_tags[*]}"
fi

if [[ ${#valid_tags[@]} -gt 1 ]]; then
  fail "HEAD has multiple release tags; keep exactly one vX.Y.Z tag: ${valid_tags[*]}"
fi

TAG="${valid_tags[0]}"
VERSION="${TAG#v}"

ci_build_number() {
  local value
  for key in \
    GITHUB_RUN_NUMBER \
    CI_PIPELINE_IID \
    CI_PIPELINE_ID \
    BUILD_NUMBER \
    BUILDKITE_BUILD_NUMBER \
    CIRCLE_BUILD_NUM \
    TRAVIS_BUILD_NUMBER \
    BITRISE_BUILD_NUMBER
  do
    value="${!key:-}"
    if [[ -n "${value}" ]]; then
      if [[ ! "${value}" =~ ^[0-9]+$ || "${value}" == "0" ]]; then
        fail "${key} must be a positive integer build number"
      fi
      printf '%s\n' "${value}"
      return 0
    fi
  done
  return 1
}

if ! BUILD_NUMBER="$(ci_build_number)"; then
  BUILD_NUMBER="$(git rev-list --count HEAD)"
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ || "${BUILD_NUMBER}" == "0" ]]; then
  fail "resolved build number must be a positive integer"
fi

DMG_NAME="Mailbell-${VERSION}.dmg"
DMG_VOLUME_NAME="Install Mailbell"

if [[ "${OUTPUT_MODE}" == "shell" ]]; then
  printf 'VERSION=%q\n' "${VERSION}"
  printf 'BUILD_NUMBER=%q\n' "${BUILD_NUMBER}"
  printf 'DMG_NAME=%q\n' "${DMG_NAME}"
  printf 'DMG_VOLUME_NAME=%q\n' "${DMG_VOLUME_NAME}"
else
  printf 'VERSION=%s\n' "${VERSION}"
  printf 'BUILD_NUMBER=%s\n' "${BUILD_NUMBER}"
  printf 'DMG_NAME=%s\n' "${DMG_NAME}"
  printf 'DMG_VOLUME_NAME=%s\n' "${DMG_VOLUME_NAME}"
fi
