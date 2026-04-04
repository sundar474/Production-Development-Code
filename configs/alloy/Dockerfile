FROM grafana/alloy:v1.2.0

COPY alloy.river /etc/alloy/config.river

EXPOSE 4317 4318 12345

ENTRYPOINT ["alloy", "run", "--server.http.listen-addr=0.0.0.0:12345", "/etc/alloy/config.river"]
