# STAGE 1
FROM nimlang/nim:2.0.2-alpine-regular as build

RUN apk add --update --no-cache openssh

RUN mkdir -p /root/.ssh/ && \
    chmod 700 /root/.ssh && \
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts
COPY ./private_ssh_key /root/.ssh/private_ssh_key
RUN chmod 600 /root/.ssh/private_ssh_key

RUN echo $'\
Host github-personal \n\
    User git \n\
    Hostname github.com \n\
    IdentityFile ~/.ssh/private_ssh_key \n\
' > ~/.ssh/config

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
