# For a quick agentless hack, the consul-client container put this binary where it's expected
# by mesh-init and then exits. The hack needs consul binary for the 'consul connect envoy' command.
cp /bin/consul /bin/consul-inject/consul

%{ if tls ~}
echo "$CONSUL_CACERT_PEM" > /consul/consul-ca-cert.pem
%{ endif ~}

%{ if https ~}
echo "$CONSUL_HTTPS_CACERT_PEM" > /consul/consul-https-ca-cert.pem
%{ endif ~}

echo "Exiting. Client not needed for agentless"
exit 0
