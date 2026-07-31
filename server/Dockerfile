# Build from repository root:
#   docker build -f server/Dockerfile -t offsend-scan .
#
# Stages a Rust staticlib (offsend-ffi) and links it into the Swift Scan API.

FROM rust:1-bookworm AS rust-build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY crates/ ./crates/
RUN cargo build -p offsend-ffi --release \
    && test -f target/release/liboffsend_ffi.a

FROM swift:6.2-jammy AS swift-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY server/ ./server/
COPY --from=rust-build /src/target/release/liboffsend_ffi.a /src/server/Vendor/OffsendFFI/liboffsend_ffi.a
COPY crates/offsend-ffi/include/offsend_ffi.h /src/server/Vendor/OffsendFFI/OffsendFFI.h
COPY crates/offsend-ffi/include/offsend_ffi.h /src/server/Vendor/OffsendFFI/offsend_ffi.h
RUN printf '%s\n' \
    'module OffsendFFI {' \
    '    header "OffsendFFI.h"' \
    '    export *' \
    '}' > /src/server/Vendor/OffsendFFI/module.modulemap

WORKDIR /src/server
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -ljemalloc \
    && BIN_PATH="$(swift build -c release --show-bin-path)" \
    && install -m 0755 "$BIN_PATH/OffsendScanAPI" /usr/local/bin/OffsendScanAPI \
    && cp -R "$BIN_PATH/OffsendScanAPI_OffsendScanAPI.resources" /usr/local/bin/

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=swift-build /usr/local/bin/OffsendScanAPI /usr/local/bin/OffsendScanAPI
COPY --from=swift-build /usr/local/bin/OffsendScanAPI_OffsendScanAPI.resources /usr/local/bin/OffsendScanAPI_OffsendScanAPI.resources

ENV PORT=8080
ENV HOST=0.0.0.0
ENV SCAN_WORK_DIR=/tmp/offsend-scan
ENV REPORT_STORAGE_DIR=/data/reports
ENV JOB_WORKERS=2

EXPOSE 8080
USER nobody
CMD ["OffsendScanAPI"]
