#!/usr/bin/env bash
# Runs a build or test command and fails when its output holds a compiler warning for a file in
# this repository, even when the command itself exits 0.
#
# Why: every target sets `.treatAllWarnings(as: .error)` (SE-0480), yet some Swift 6 diagnostics,
# such as a captured var mutated in a closure passed to `DispatchQueue.async`, stay warnings under
# it, so `swift build` exits 0 with `warning:` lines in its log. A warning counts when its file is
# inside the repository and outside every `.build*` folder; dependency checkouts and SwiftPM's own
# path-less warnings do not.
#
# Usage: scripts/fail-on-warnings.sh -- <command> [argument...]
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "usage: scripts/fail-on-warnings.sh -- <command> [argument...]"
}
usage_error() {
  echo "fail-on-warnings: $1" >&2
  usage >&2
  exit 2
}

separated=0
while (( $# )); do
  case $1 in
    --help) usage; exit 0 ;;
    --) shift; separated=1; break ;;
    *) usage_error "unknown option '$1'" ;;
  esac
done
(( separated )) || usage_error "missing '--' before the command"
(( $# )) || usage_error "no command after '--'"

root=$(pwd -P)
logical=$PWD
log=$(mktemp "${TMPDIR:-/tmp}/fail-on-warnings.XXXXXX")
trap 'rm -f "$log"' EXIT

status=0
"$@" 2>&1 | tee "$log" || status=$?
if (( status )); then
  echo "fail-on-warnings: '$*' exited $status" >&2
  exit 1
fi

# A diagnostic line is `<path>:<line>[:<column>]: warning: <message>`. The compiler colours it even
# into a pipe, so ANSI colour (CSI) and hyperlink (OSC 8) sequences are removed first.
warnings=()
files=()
while IFS= read -r line; do
  # `.+` is greedy, so the column form is tried first; otherwise the line number joins the path.
  if [[ $line =~ ^(.+):[0-9]+:[0-9]+:\ warning: ]] || [[ $line =~ ^(.+):[0-9]+:\ warning: ]]; then
    path=${BASH_REMATCH[1]}
  else
    continue
  fi
  [[ $path == /* ]] || path=$root/$path
  if [[ $path == "$root"/* ]]; then
    relative=${path#"$root"/}
  elif [[ $path == "$logical"/* ]]; then
    relative=${path#"$logical"/}
  else
    continue
  fi
  case "/$relative/" in
    */.build*|*/../*) continue ;;
  esac
  warnings+=("$line")
  files+=("$root/$relative")
done < <(perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\e\].*?\e\\//g' "$log")

(( ${#warnings[@]} )) || exit 0

unique=$(printf '%s\n' "${warnings[@]}" | sort -u)
count=$(printf '%s\n' "$unique" | wc -l | tr -d ' ')
echo "fail-on-warnings: $count compiler warning(s) in project files:" >&2
printf '%s\n' "$unique" >&2
# An incremental build does not replay an up-to-date file's warnings, so the next run would pass.
# Touching each reported file makes it recompile, and the failure stays until the warning is fixed.
for file in "${files[@]}"; do
  [[ -f $file ]] && touch "$file"
done
exit 1
