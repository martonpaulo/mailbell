#!/usr/bin/env bash

mailbell_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

mailbell_strip_matching_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    local first="${value:0:1}"
    local last="${value: -1}"
    if [[ "${first}" == "${last}" && ( "${first}" == "'" || "${first}" == '"' ) ]]; then
      printf '%s' "${value:1:${#value}-2}"
      return
    fi
  fi
  printf '%s' "${value}"
}

mailbell_is_allowed_env_key() {
  case "$1" in
    MAILBELL_GOOGLE_CLIENT_ID|\
    MAILBELL_GOOGLE_CLIENT_SECRET|\
    MAILBELL_BUNDLE_ID|\
    MAILBELL_CODE_SIGN_IDENTITY|\
    MAILBELL_NOTARY_KEYCHAIN_PROFILE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mailbell_load_dotenv() {
  local dotenv_path="${MAILBELL_DOTENV_PATH:-.env}"
  [[ -f "${dotenv_path}" ]] || return 0

  local raw line key value
  while IFS= read -r raw || [[ -n "${raw}" ]]; do
    line="$(mailbell_trim "${raw}")"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue

    key="$(mailbell_trim "${line%%=*}")"
    value="$(mailbell_trim "${line#*=}")"
    mailbell_is_allowed_env_key "${key}" || continue

    if [[ -z "${!key:-}" ]]; then
      value="$(mailbell_strip_matching_quotes "${value}")"
      export "${key}=${value}"
    fi
  done < "${dotenv_path}"
}

mailbell_update_dotenv_values() {
  local dotenv_path="${MAILBELL_DOTENV_PATH:-.env}"
  python3 - "${dotenv_path}" "$@" <<'PY'
import sys
from pathlib import Path

allowed = {
    "MAILBELL_GOOGLE_CLIENT_ID",
    "MAILBELL_GOOGLE_CLIENT_SECRET",
    "MAILBELL_BUNDLE_ID",
    "MAILBELL_CODE_SIGN_IDENTITY",
    "MAILBELL_NOTARY_KEYCHAIN_PROFILE",
}

path = Path(sys.argv[1])
pairs = sys.argv[2:]
if len(pairs) % 2 != 0:
    raise SystemExit("mailbell_update_dotenv_values expects key/value pairs")

updates = dict(zip(pairs[0::2], pairs[1::2]))
unknown = sorted(set(updates) - allowed)
if unknown:
    raise SystemExit(f"unsupported .env key: {', '.join(unknown)}")

lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
seen = set()
result = []

for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        result.append(line)
        continue

    key = line.split("=", 1)[0].strip()
    if key in updates:
        result.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        result.append(line)

for key, value in updates.items():
    if key not in seen:
        result.append(f"{key}={value}")

path.write_text("\n".join(result).rstrip() + "\n", encoding="utf-8")
PY
}
