#!/bin/zsh
# Test helper: drives a running debug app. Usage: drive.sh <pid> <dir> "line1" "line2" ...
pid=$1; dir=$2; shift 2
rm -f "$dir/done"
printf '%s\n' "$@" > "$dir/cmd"
kill -USR1 "$pid"
for i in {1..50}; do [[ -f "$dir/done" ]] && break; sleep 0.1; done
