#!/usr/bin/env bash
# The full test suite, one file at a time (flutter test --concurrency=1), with an honest re-run.
#
# On this PC flutter_tester.exe now and then crashes natively (exit code -1073741819 =
# 0xC0000005, or "Connection closed before test suite loaded"): the runner, not the app
# (PROGRESS.md "Lost test processes: cause found"). Such a file is run once more, alone:
#   passes alone            -> RUNNER CRASH (printed with the exit code, counted, not a fail)
#   fails or dies alone     -> FAIL
#   a real failure (an expectation, an exception) is never re-run and always FAILs.
#
# Run from app\:  bash ../tools/run_tests.sh      (log in ../work/test-last.log, verbose runner log)
set -u
cd "$(dirname "$0")/../app" || exit 2
source ../tools/env.sh
log=../work/test-last.log
flutter test --concurrency=1 -v "$@" > "$log" 2>&1
code=$?
total=$(grep -oE '^[0-9]+:[0-9]+ \+[0-9]+' "$log" | tail -1 | grep -oE '\+[0-9]+')
if [ $code -eq 0 ] && ! grep -qE " FAIL|did not complete|Connection closed" "$log"; then
  echo "PASSED, 0 runner crashes: $total, all tests passed"
  exit 0
fi
# a real failure: an [E] line that is not a lost process
real=$(grep -E "^[0-9]+:[0-9]+ .*\[E\]" "$log" | grep -vE "did not complete|loading .*\[E\]" | head -5)
if [ -n "$real" ] || grep -qE "Expected:|EXCEPTION CAUGHT" "$log"; then
  echo "FAIL (a test failed):"
  grep -nE "^[0-9]+:[0-9]+ .*\[E\]|Expected:|Actual:|EXCEPTION CAUGHT" "$log" | head -20
  exit 1
fi
files=$(grep -oE "[A-Za-z]:/[^ \"]*_test\.dart" "$log" | sort -u | while read -r f; do
  if grep -E "$f.*(did not complete|\[E\])|Failed to load \"$f\"" "$log" > /dev/null; then echo "$f"; fi
done)
if [ -z "$files" ]; then
  echo "FAIL (exit $code), nothing to re-run:"; tail -5 "$log"; exit 1
fi
n=0
for f in $files; do
  # the runner's number for this file, and how its flutter_tester ended
  num=$(grep -iE "test [0-9]+: starting test $f" "$log" | head -1 | grep -oE "test [0-9]+" | grep -oE "[0-9]+")
  exitc=$( [ -n "$num" ] && grep -E "test $num: flutter_tester process at pid [0-9]+ exited with code=" "$log" | head -1 | grep -oE "code=-?[0-9]+" )
  why=$(grep -E "Failed to load \"$f\"|$f.*did not complete" "$log" | head -1 | grep -oE 'Connection closed[^.]*|did not complete' | head -1)
  flutter test "$f" > "$log.rerun" 2>&1
  rc=$?
  if [ $rc -ne 0 ] || grep -qE "did not complete|Connection closed" "$log.rerun"; then
    echo "FAIL: $f also fails or dies alone ($why, ${exitc:-no exit code})"
    grep -nE "\[E\]|Expected|Actual|did not complete|Connection closed" "$log.rerun" | head
    exit 1
  fi
  n=$((n + 1))
  echo "RUNNER CRASH: $f ($why, ${exitc:-no exit code}); passes alone: $(tail -1 "$log.rerun")"
done
echo "PASSED with $n RUNNER CRASH(ES) (main run $total); put the RUNNER CRASH lines in the commit or done report and the tally"
exit 0
