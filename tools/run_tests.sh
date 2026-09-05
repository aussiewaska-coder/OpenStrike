#!/usr/bin/env bash
set -u

test_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
test_logs=$(mktemp -d /tmp/openstrike-tests.XXXXXX)
printf 'Logs: %s\n' "$test_logs"
if [ "$#" -eq 0 ]; then
  set -- "$test_root"/tests/*_test.gd
fi
failures=0
total=0
for test_file in "$@"; do
  total=$((total + 1))
  test_name=${test_file##*/}
  case "$test_file" in
    /*) ;;
    *) test_file="$test_root/$test_file" ;;
  esac
  test_log="$test_logs/$test_name.log"
  timeout "${TEST_TIMEOUT_SECONDS:-45}" "$godot_bin" --headless --path "$test_root" --script "$test_file" > "$test_log" 2>&1
  result=$?
  # Some older SceneTree tests call quit(1), then overwrite it with quit(0).
  # Renderer errors can also leave exit=0. Neither is a passing test.
  if [ "$result" -ne 0 ] || rg -q 'SCRIPT ERROR:|^ERROR:|Assertion failed' "$test_log" || ! rg -q 'TEST_PASS' "$test_log"; then
    failures=$((failures + 1))
    printf 'FAIL %s (exit %s)\n' "$test_name" "$result"
    rg -m 3 'SCRIPT ERROR:|^ERROR:|Assertion failed' "$test_log" || true
  else
    printf 'PASS %s\n' "$test_name"
  fi
done
printf '%s/%s passed\n' "$((total - failures))" "$total"
[ "$failures" -eq 0 ]
