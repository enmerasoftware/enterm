#!/bin/zsh
# Measures what Enterm costs while it sits there: CPU and memory of the app and its session service.
# Usage: scripts/measure.sh [seconds, default 60]. Start Enterm first and leave it idle.
# Prints one line per process and a total, ready to paste into an issue or the README.
set -e
seconds=${1:-60}
pids=()
for name in EntermApp entermd; do
  for pid in $(pgrep -x "$name" 2>/dev/null); do pids+=($pid); done
done
if (( ${#pids} == 0 )); then
  echo "Enterm çalışmıyor. Önce uygulamayı açın." >&2
  exit 1
fi
typeset -A cpu rss names
for pid in $pids; do cpu[$pid]=0; rss[$pid]=0; names[$pid]=$(ps -o comm= -p $pid | xargs basename); done
samples=0
for (( i = 0; i < seconds; i++ )); do
  for pid in $pids; do
    line=($(ps -o %cpu=,rss= -p $pid 2>/dev/null || true))
    (( ${#line} == 2 )) || continue
    cpu[$pid]=$(( ${cpu[$pid]} + ${line[1]} ))
    rss[$pid]=$(( ${rss[$pid]} + ${line[2]} ))
  done
  (( samples++ ))
  sleep 1
done
total_cpu=0; total_mb=0
echo "Enterm boşta, $seconds saniye ($(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string)):"
for pid in $pids; do
  c=$(( ${cpu[$pid]} / samples )); m=$(( ${rss[$pid]} / samples / 1024 ))
  printf "  %-10s işlemci %%%.1f  bellek %d MB\n" ${names[$pid]} $c $m
  total_cpu=$(( total_cpu + c )); total_mb=$(( total_mb + m ))
done
printf "  Toplam     işlemci %%%.1f  bellek %d MB\n" $total_cpu $total_mb
