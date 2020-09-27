#!/bin/bash

CPU_LIMIT_CORE_AC=40
CPU_LIMIT_CORE_BATTERY=10

case "$(pmset -g batt | grep 'Now drawing from')" in
*Battery*) CPU_LIMIT_CORE=${CPU_LIMIT_CORE_BATTERY} ;;
*)         CPU_LIMIT_CORE=${CPU_LIMIT_CORE_AC} ;;
esac

function terminator() { 
  kill -TERM "${duplicacy}" 2>/dev/null
  kill -TERM "${throttler}" 2>/dev/null
}

trap terminator SIGHUP SIGINT SIGQUIT SIGTERM EXIT

/usr/local/bin/duplicacy backup & duplicacy=$!

/usr/local/bin/cpulimit --limit=${CPU_LIMIT_CORE} --include-children --pid=${duplicacy} & throttler=$!

wait ${throttler} 
