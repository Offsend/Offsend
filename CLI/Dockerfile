# Build from repository root:
#   docker build -f CLI/Dockerfile -t offsend/cli .
#   docker run --rm offsend/cli check --help
FROM swift:6.0.3-jammy AS build

ARG OFFSEND_CLI_VERSION=0.0.0
ENV OFFSEND_CLI_VERSION=$OFFSEND_CLI_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY Package.swift ./
COPY Package.resolved* ./
COPY Scripts/build_linux_cli.sh ./Scripts/build_linux_cli.sh
COPY Core/ ./Core/
COPY CLI/ ./CLI/

RUN bash Scripts/build_linux_cli.sh \
    && install -m 0755 "$(swift build -c release --show-bin-path)/offsend" /usr/local/bin/offsend

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bin/offsend /usr/local/bin/offsend

ENTRYPOINT ["offsend"]
CMD ["--help"]
