FROM prom/prometheus:v2.52.0 AS prometheus
FROM quay.io/thanos/thanos:v0.35.0 AS thanos

# Use a base image that can run both processes
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries
COPY --from=prometheus /bin/prometheus /bin/prometheus
COPY --from=thanos     /bin/thanos     /bin/thanos

# Copy configs
COPY prometheus.yaml       /etc/prometheus/prometheus.yaml
COPY thanos-sidecar.yaml   /etc/thanos/sidecar.yaml
COPY supervisord.conf      /etc/supervisor/conf.d/supervisord.conf

# Prometheus data dir
RUN mkdir -p /prometheus /etc/prometheus/rules
VOLUME ["/prometheus"]

EXPOSE 9090 10901 10902

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
