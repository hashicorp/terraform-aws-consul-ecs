# For a quick agentless hack, the consul-client container put this binary where it's expected
# by mesh-init and then exits. The hack needs consul binary for the 'consul connect envoy' command.
cp /bin/consul /bin/consul-inject/consul

echo "Exiting. Client not needed for agentless"
exit 0
