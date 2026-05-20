ARG ELIXIR_VERSION=1.17.2
ARG OTP_VERSION=27.0.1
ARG DEBIAN_VERSION=bookworm-20240722-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"

###############################################################
FROM ${BUILDER_IMAGE} AS builder
LABEL maintainer="info@electric-sql.com"

RUN apt-get update -y && \
  apt-get install -y build-essential git curl && \
  apt-get clean && \
  rm -f /var/lib/apt/lists/*_*

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

WORKDIR /app

COPY config/*.exs /app/config/
COPY mix.exs mix.lock /app/

# The mix.exs has electric_client as a local path dep for development, but the
# path isn't available inside the Docker build context. Swap it to the git dep
# (which matches what mix.lock has) for the build.
RUN sed -i 's|{:electric_client, path:.*}|{:electric_client, github: "electric-sql/electric", branch: "main", subdir: "packages/elixir-client", depth: 1}|' mix.exs

# Remove the stale lock entry for electric_client so deps.get fetches the
# latest from the main branch rather than trying to checkout a pinned SHA
# that isn't reachable in a shallow clone.
RUN sed -i '/^  "electric_client"/d' mix.lock

RUN mix do deps.get + deps.compile

# These are ordered by change frequency, with the least frequently changing dir first.
COPY lib /app/lib/

ARG ELECTRIC_VERSION

RUN mix compile

ENV CLIENT_COUNT="50000"

# ENTRYPOINT ["mix", "gen.load", "--table", "items"]
# ENTRYPOINT ["mix"]
CMD ["mix", "run", "--no-halt"]
