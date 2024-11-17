# Use a base image with Ubuntu
FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install curl jq -y && \
    apt clean all

# Download and install cfssl binaries (v1.6.5)
RUN curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64 -o /usr/local/bin/cfssl && \
    curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64 -o /usr/local/bin/cfssljson && \
    chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

# Copy configuration files and entrypoint script into the container
COPY config/entrypoint.sh /entrypoint.sh

COPY config/cfssl-config.json /etc/cfssl/config/cfssl-config.json
COPY config/csr_root_ca.json /etc/cfssl/config/csr_root_ca.json
COPY config/csr_intermediate_ca.json /etc/cfssl/config/csr_intermediate_ca.json
COPY config/ocsp.csr.json /etc/cfssl/config/ocsp.csr.json
COPY config/db_config.json /etc/cfssl/config/db_config.json

# Make the entrypoint script executable
RUN chmod +x /entrypoint.sh

# Expose necessary ports for cfssl and ocsp
EXPOSE 8888 8889

RUN mkdir /etc/cfssl/certs

# Set the entrypoint for the container
CMD ["/entrypoint.sh"]
