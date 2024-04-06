# STAGE 1
FROM nimlang/nim:2.0.2-alpine-regular as build

WORKDIR /build

COPY nim.cfg .
COPY config.nims .
COPY nimble.lock .
COPY ny.nimble .

RUN nimble refresh
RUN nimble install --depsOnly

COPY src src
RUN nimble build --mm:arc -d:release -d:danger -d:lto --passC:-flto --passL:-flto


# STAGE 2
FROM alpine as runtime

RUN apk add --update --no-cache libpq-dev tzdata

WORKDIR /ny

COPY --from=build /build/bin /ny/bin
