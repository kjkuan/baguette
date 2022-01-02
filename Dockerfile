FROM golang:1.11.5-alpine AS build

RUN apk add git
WORKDIR /root
ENV CGO_ENABLED=0
RUN git clone https://github.com/matvore/websocketd \
    && cd websocketd \
    && go build \
    && ./websocketd --version

# --------------------
FROM alpine:3.21

COPY --from=build /root/websocketd/websocketd /usr/local/bin/websocketd
RUN apk --no-cache add \
    bash \
    coreutils \
    jq \
    cmark

RUN adduser -D -s /bin/bash baguette \
    && install -o baguette -g baguette -d /home/baguette/baguette

WORKDIR /home/baguette

USER baguette
ENV PATH /home/baguette/baguette:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CMD ["/bin/bash"]
