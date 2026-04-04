FROM grafana/tempo:2.5.0

COPY tempo.yaml /etc/tempo/tempo.yaml

EXPOSE 3200 4317 4318 9095

ENTRYPOINT ["tempo", "-config.file=/etc/tempo/tempo.yaml", "-config.expand-env=true"]
