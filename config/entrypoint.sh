#!/bin/bash

# Check if the necessary environment variables are set
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_HOST" ] || [ -z "$POSTGRES_DB" ]; then
  echo "Missing required environment variables. Exiting."
  exit 1
fi

# Build the PostgreSQL connection string
json="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB?sslmode=disable"

# Use jq to modify the db_config.json file
if [ -f /etc/cfssl/config/db_config.json ]; then
  jq --arg json "$json" '.data_source = $json' /etc/cfssl/config/db_config.json > /tmp/db_config.json && mv /tmp/db_config.json /etc/cfssl/config/db_config.json
  echo "Updated db_config.json with the new connection string."
else
  echo "/etc/cfssl/config/db_config.json not found. Skipping update."
fi


# Check if the certificates already exist; if not, generate them
if [ ! -f /etc/cfssl/certs/root_ca.pem ]; then
    echo "Root CA certificate not found, generating it..."
    cfssl gencert -initca /etc/cfssl/config/csr_root_ca.json | cfssljson -bare /etc/cfssl/certs/root_ca
fi

if [ ! -f /etc/cfssl/certs/intermediate_ca.pem ]; then
    echo "Intermediate CA certificate not found, generating it..."
    cfssl gencert -initca /etc/cfssl/config/csr_intermediate_ca.json | cfssljson -bare /etc/cfssl/certs/intermediate_ca
    cfssl sign -ca /etc/cfssl/certs/root_ca.pem -ca-key /etc/cfssl/certs/root_ca-key.pem -config="/etc/cfssl/config/cfssl-config.json" -profile="intermediate" /etc/cfssl/certs/intermediate_ca.csr | cfssljson -bare /etc/cfssl/certs/intermediate_ca
fi

if [ ! -f /etc/cfssl/certs/ocsp.pem ]; then
    echo "OCSP certificate not found, generating it..."
    cfssl gencert -ca /etc/cfssl/certs/intermediate_ca.pem -ca-key /etc/cfssl/certs/intermediate_ca-key.pem -config="/etc/cfssl/config/cfssl-config.json" -profile="ocsp" /etc/cfssl/config/ocsp.csr.json | cfssljson -bare /etc/cfssl/certs/ocsp
fi

# Dump OCSP data before starting the CFSSL service
echo "Generating OCSP dump..."
cfssl ocspdump -loglevel=0 -db-config /etc/cfssl/config/db_config.json > /etc/cfssl/certs/ocspdump

# Start CFSSL server and OCSP responder
echo "Starting CFSSL server on port 8888..."
cfssl serve -address=0.0.0.0 -port=8888 \
    -ca /etc/cfssl/certs/intermediate_ca.pem \
    -ca-key /etc/cfssl/certs/intermediate_ca-key.pem \
    -db-config /etc/cfssl/config/db_config.json \
    -config /etc/cfssl/config/cfssl-config.json \
    -responder=/etc/cfssl/certs/ocsp.pem \
    -responder-key=/etc/cfssl/certs/ocsp-key.pem \
    >> /dev/null &

# Start OCSP service
echo "Starting OCSP responder on port 8889..."
cfssl ocspserve -port=8889 -responses=/etc/cfssl/certs/ocspdump >> /dev/null &

# Keep the container running by tailing a dummy log
tail -f /dev/null
