FROM otel/opentelemetry-collector-contrib:0.100.0

# Copy gateway config
COPY otelcol-gateway.yaml /etc/otelcol-contrib/config.yaml

# Expose OTLP gRPC, HTTP, health check, metrics, zpages
EXPOSE 4317 4318 13133 8888 55679

CMD ["--config=/etc/otelcol-contrib/config.yaml"]
