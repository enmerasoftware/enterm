#!/bin/zsh
# Test helper: restarts the debug app on a throwaway configuration under /tmp/et.
[[ -f /tmp/et/pid ]] && kill $(cat /tmp/et/pid) 2>/dev/null
if [[ "$1" == "fresh" ]]; then
  pkill_pid=$(cat /tmp/et/home/daemon.pid 2>/dev/null)
  ps -axo pid=,comm= | awk '/Enterm.app\/Contents\/MacOS\/entermd/{print $1}' | while read p; do
    lsof -p $p 2>/dev/null | grep -q /tmp/et/e.sock && kill $p
  done
  rm -rf /tmp/et/home
fi
mkdir -p /tmp/et /tmp/et/bin
PATH=/tmp/et/bin:$PATH ENTERM_DEBUG_DIR=/tmp/et ENTERM_HOME=/tmp/et/home ENTERM_SOCKET=/tmp/et/e.sock nohup ${0:A:h:h}/build/Enterm.app/Contents/MacOS/EntermApp > /tmp/et/app.log 2>&1 &
echo $! > /tmp/et/pid
sleep ${2:-3}
