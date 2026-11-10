FROM        quay.io/prometheus/busybox:latest

LABEL       org.opencontainers.image.title="kafka_exporter" \
            org.opencontainers.image.description="Prometheus exporter for Apache Kafka" \
            org.opencontainers.image.source="https://github.com/devbykidle/kafka_exporter" \
            org.opencontainers.image.licenses="Apache-2.0"

# TARGETARCH is injected by BuildKit for every --platform of a multi-arch build.
# Do not give it a default: a default would override the automatic value and make
# every platform copy the amd64 binary.
ARG TARGETARCH
ARG BIN_DIR=.build/linux-${TARGETARCH}

COPY ${BIN_DIR}/kafka_exporter /bin/kafka_exporter

EXPOSE     9308
USER nobody
ENTRYPOINT [ "/bin/kafka_exporter" ]
