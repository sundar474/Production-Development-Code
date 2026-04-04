FROM grafana/loki:3.0.0

COPY loki.yaml /etc/loki/loki.yaml

EXPOSE 3100 9095 7946

ENTRYPOINT ["loki", "-config.file=/etc/loki/loki.yaml", "-config.expand-env=true"]
