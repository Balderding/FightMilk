#!/usr/bin/env bash
# The release gate (PLAN-next change 14): every test file run ALONE, one after another (light
# load), each exit code kept, and ALL the output searched for " FAIL", "[E]" and "did not
# complete": never judged by the last line. Writes work/release/gate-<version>.txt.
# Run from app/:  bash ../tools/release_gate.sh 0.9.0
set -u
ver="${1:-next}"
out="../work/release"
mkdir -p "$out/gate-logs"
report="$out/gate-$ver.txt"
: > "$report"
pass=0
fail=0
for f in test/*_test.dart; do
  name="$(basename "$f" .dart)"
  log="$out/gate-logs/$name.log"
  flutter test --concurrency=1 "$f" > "$log" 2>&1
  rc=$?
  # an empty count (grep itself could not start) is never a pass: it forces a re-run
  bad=$(grep -cE " FAIL|\[E\]|did not complete" "$log")
  [ -n "$bad" ] || bad="?"
  if [ "$rc" -eq 0 ] && [ "$bad" = "0" ]; then
    pass=$((pass + 1))
    echo "ok    $name (exit 0, 0 marks)" >> "$report"
  else
    case "$rc" in
      127) why="shell could not start the command (fork failed), re-run" ;;
      0) why="marks could not be counted (grep did not start), re-run" ;;
      *) [ "$rc" -eq 255 ] || [ "$rc" -gt 128 ] && why="the test runner crashed (exit $rc), re-run" || why="tests failed (exit $rc), re-run" ;;
    esac
    [ "$bad" = "?" ] || [ "$bad" = "0" ] || why="$bad failure marks, re-run"
    flutter test --concurrency=1 "$f" > "$log.again" 2>&1
    rc2=$?
    bad2=$(grep -cE " FAIL|\[E\]|did not complete" "$log.again")
    [ -n "$bad2" ] || bad2="?"
    if [ "$rc2" -eq 0 ] && [ "$bad2" = "0" ]; then
      pass=$((pass + 1))
      echo "ok*   $name (first run: exit $rc, $bad marks: $why; second run: exit $rc2, $bad2 marks)" >> "$report"
    else
      fail=$((fail + 1))
      echo "FAIL  $name (first run: exit $rc, $bad marks: $why; second run: exit $rc2, $bad2 marks)" >> "$report"
    fi
  fi
done
{
  echo
  echo "files: $((pass + fail)), passed: $pass, failed: $fail"
  echo "grep of all output for ' FAIL', '[E]', 'did not complete' in files that passed:"
  grep -lE " FAIL|\[E\]|did not complete" "$out"/gate-logs/*.log 2>/dev/null | sed 's/^/  marks in first run: /' || true
} >> "$report"
tail -3 "$report"
[ "$fail" -eq 0 ]
