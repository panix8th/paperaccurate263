#!/usr/bin/env bash
# Boots the Paper server in the given directory, runs the plugin's command from the console,
# stops it again and checks the log.
set -uo pipefail

dir="${1:?usage: server-test.sh <server-dir>}"
cd "$dir"

echo "eula=true" > eula.txt
cat > server.properties <<'PROPS'
online-mode=false
level-type=minecraft\:flat
generate-structures=false
spawn-protection=0
PROPS

log=server-out.log
rm -f console "$log"
mkfifo console
exec 3<>console   # keep the fifo open so the server never sees EOF on stdin

java -Xms1G -Xmx2G -jar paper.jar --nogui <console >"$log" 2>&1 &
pid=$!

fail() {
  echo "::error::$1"
  kill "$pid" 2>/dev/null
  echo "----- server log -----"
  cat "$log"
  exit 1
}

for _ in $(seq 1 600); do
  grep -q 'Done (' "$log" && break
  kill -0 "$pid" 2>/dev/null || fail "server exited before finishing startup"
  sleep 1
done
grep -q 'Done (' "$log" || fail "server did not finish starting within 10 minutes"

send() { echo "$1" >&3; sleep 3; }
send "version PaperAccurateBlockPlacement"
send "abp"
send "abp reload"
send "stop"

for _ in $(seq 1 120); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
kill -0 "$pid" 2>/dev/null && fail "server did not stop"

echo "----- server log -----"
cat "$log"
echo "----------------------"

status=0
check() {  # check <description> <grep -E pattern>
  if grep -Eq "$2" "$log"; then echo "PASS: $1"; else echo "::error::FAIL: $1"; status=1; fi
}
check_absent() {
  if grep -Eiq "$2" "$log"; then
    echo "::error::FAIL: $1"; grep -Ei "$2" "$log"; status=1
  else
    echo "PASS: $1"
  fi
}

check "packetevents enabled" 'Enabling packetevents'
check "plugin enabled" 'PaperAccurateBlockPlacement loaded! Protocol: v3'
check "/abp prints the version" 'PaperAccurateBlockPlacement v[0-9]'
check "/abp reload works" 'PaperAccurateBlockPlacement config reloaded'
check_absent "no load/enable errors" 'Could not load .*PaperAccurateBlockPlacement|Error occurred while (enabling|disabling) PaperAccurateBlockPlacement|Error occurred while (enabling|disabling) packetevents|Unknown or incomplete command'
check_absent "no plugin exceptions" '(Exception|Error).*(accurateblockplacement|packetevents)'

exit $status
