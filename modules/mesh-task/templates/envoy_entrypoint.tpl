onterm() {
    echo "Ignored sigterm to support graceful task shutdown."
    if [ "$ENVOY_PID" ]; then
        # Second wait. This returns when a trapped signal is received
        # (and then, the onterm handler function is run and we arrive back here)
        wait $ENVOY_PID
    fi
}

trap onterm TERM

# Note: We cannot exec here, because that loses our traps.
$0 "$@" &
ENVOY_PID=$!

# First wait. This returns when a signal is received for which a trap has been set.
wait $ENVOY_PID
