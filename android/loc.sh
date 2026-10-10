#!/usr/bin/env bash
# Code-size gate: counts Kotlin lines excluding blanks and comments; warns over 300, fails over 400.
# ponytail: line-based comment stripping (// lines and /* */ blocks); a /* inside a string would fool it.
cd "$(dirname "$0")"
fail=0
for f in $(find app/src -name '*.kt'); do
  n=$(awk '
    /^[[:space:]]*\/\*/ { inblock = 1 }
    inblock { if ($0 ~ /\*\//) inblock = 0; next }
    /^[[:space:]]*(\/\/|$)/ { next }
    { n++ } END { print n + 0 }' "$f")
  if [ "$n" -gt 400 ]; then echo "FAIL $n $f"; fail=1
  elif [ "$n" -gt 300 ]; then echo "warn $n $f"; fi
done
exit $fail
