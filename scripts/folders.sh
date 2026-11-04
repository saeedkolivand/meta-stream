#!/usr/bin/env bash
# Folder-size check (warn only): a source folder holding more than 15 Swift/Kotlin files should split by sub-feature
# (a noun: Widgets/Goal), never by file type. See adr/0007-feature-modules-mirrored-across-platforms.md.
cd "$(dirname "$0")/.."
find MetaStream MetaStreamTests Packages android -type f \( -name '*.swift' -o -name '*.kt' \) \
  -not -path '*/build/*' -not -path '*/.build/*' -not -path 'android/build-logic/*' -printf '%h\n' |
  sort | uniq -c | awk '$1 > 15 { print "warn " $1 " files in " $2 }'
exit 0
