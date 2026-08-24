#!/usr/bin/env bash

cd "${SHOPWARE_FOLDER}" || exit 1

WORKER_AMOUNT="$3"
WORKER_TRANSPORT="$4"

if [[ -z "$WORKER_AMOUNT" ]]; then
  WORKER_AMOUNT=1;
fi
if [[ -z "$WORKER_TRANSPORT" ]]; then
  WORKER_TRANSPORT="async";
fi

TRAP_PIDS="/tmp/${SHOPWARE_PROJECT}-${WORKER_TRANSPORT}-worker.pid"

function cancel_trap()
{
  for i in $(seq 1 "${WORKER_AMOUNT}"); do
    PID=$(cat "${TRAP_PIDS}.$i");

    if [[ -n $PID ]]; then
      kill -9 "$PID"
      rm "${TRAP_PIDS}.$i"
    fi
  done
}

trap cancel_trap SIGINT

for i in $(seq 1 "${WORKER_AMOUNT}"); do
  bash -c "while true; do php bin/console messenger:consume ${WORKER_TRANSPORT} --memory-limit=1G -vvv; done"  > "var/log/worker-${WORKER_TRANSPORT}-$i.log" 2>&1 & echo $! > "${TRAP_PIDS}.$i"
done

echo "Started ${WORKER_AMOUNT} worker(s) for the \"${WORKER_TRANSPORT}\" transport in the background. Press CTRL+C to cancel them. Use swdc worker-logs to see logs"

wait