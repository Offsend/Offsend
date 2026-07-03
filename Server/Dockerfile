# Build from repository root:
#   docker build -f Server/Dockerfile -t offsend-scan .
FROM swift:6.0-jammy AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    rsync \
    libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY Server/ ./Server/
COPY Core/ ./Core/
COPY Scripts/sync_scan_vendor.sh ./Scripts/sync_scan_vendor.sh
RUN bash Scripts/sync_scan_vendor.sh

WORKDIR /src/Server
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc \
    && install -m 0755 .build/release/OffsendScanAPI /usr/local/bin/OffsendScanAPI

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bin/OffsendScanAPI /usr/local/bin/OffsendScanAPI

ENV PORT=8080
ENV HOST=0.0.0.0
ENV SCAN_WORK_DIR=/tmp/offsend-scan
ENV REPORT_STORAGE_DIR=/data/reports
ENV JOB_WORKERS=2

EXPOSE 8080
USER nobody
CMD ["OffsendScanAPI"]
