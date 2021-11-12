$0 "$@" &
export PID=$!

onterm() {
    echo "consul-ecs: received sigterm. waiting ${application_shutdown_delay_seconds}s before terminating application."
    sleep ${application_shutdown_delay_seconds}
    exit 0
}

onexit() {
    if [ -n "$PID" ]; then
        kill $PID
        wait $PID
    fi
}

trap onterm TERM
trap onexit EXIT
wait $PID
