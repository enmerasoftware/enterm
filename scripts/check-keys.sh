#!/bin/zsh
# A key the window uses must not reach the terminal: Esc would stop a running agent.
# Needs a debug build in build/test. Runs on a throwaway configuration and exits non-zero on a leak.
root=${0:A:h:h}
cd "$root"
scripts/run-test.sh fresh 5
pid=$(cat /tmp/et/pid)
d() { scripts/drive.sh $pid /tmp/et "$@"; sleep 1; }
count() {
  d "tail /tmp/et/keys.txt"
  sleep 1
  python3 -c "print(open('/tmp/et/keys.txt',errors='ignore').read().count('^['))"
}
d "type cat\\r"
sleep 1
failed=0
for page in newSession palette menu settings; do
  d "do $page"
  sleep 1
  d "key esc"
  sleep 1
  n=$(count)
  echo "$page kapandı: $n"
  [[ "$n" == "0" ]] || failed=1
done
# Focus returns to the terminal a moment after a cover closes.
sleep 3
d "key esc"
sleep 2
n=$(count)
echo "kapak yokken Esc terminale gider: $n"
[[ "$n" == "1" ]] || failed=1
kill $pid
sleep 1
ps -axo pid=,command= | awk '/test\/Enterm.app\/Contents\/MacOS\/entermd/{print $1}' | while read p; do kill $p; done
exit $failed
