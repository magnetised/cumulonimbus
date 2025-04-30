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
COPY mix.* /app/
RUN mix do deps.get + deps.compile

# These are ordered by change frequency, with the least frequently changing dir first.
COPY lib /app/lib/

ARG ELECTRIC_VERSION

RUN mix compile

ENV CLIENT_COUNT="50000"

# ENTRYPOINT ["mix", "gen.load", "--table", "items"]
# ENTRYPOINT ["mix"]
CMD ["mix", "run", "--no-halt"]
