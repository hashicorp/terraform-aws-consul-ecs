SHELL = bash

CONSUL_DC?=dc1
CONSUL_COUNT?=3
NODE_NAME?=consul
ADDITIONAL_DNSNAMES?=()

# Build CA & Certs for Consul
.PHONY: certs
certs: clean-certs
	ADD_NAMES=""
	# Creating CA and CA-Key
	consul tls ca create
	# Creating Client and CLI key pairs
	for I in "-client" "-cli"; do \
	    consul tls cert create $$I -dc $(CONSUL_DC); \
	done;
	# Creating Consul ALB Cert
	for J in "$(ADDITIONAL_DNSNAMES)"; do \
		ADD_NAMES="$$ADD_NAMES -additional-dnsname=$${J}"; \
	done;
	consul tls cert create -server \
		-node="consul" \
		-dc="$(CONSUL_DC)" \
		-additional-dnsname="consul.$(CONSUL_DC)" \
		$$ADD_NAMES;

# Clean out local CA & Cert
.PHONY: clean-certs
clean-certs:
	rm -f *.pem
