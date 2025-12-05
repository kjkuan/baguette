ARG ALPINE_TAG=3.20
ARG CMARK_GFM_TAG=0.29.0.gfm.13

# Build GitHub's CommonMark fork
# --------------------------------
FROM alpine:$ALPINE_TAG AS cmark-gfm-build
ARG CMARK_GFM_TAG

RUN apk add git build-base make cmake python3
WORKDIR /root
RUN git clone https://github.com/github/cmark-gfm.git \
    && cd cmark-gfm \
    && git checkout ${CMARK_GFM_TAG?} \
    && make \
    && make test \
    && make install

# Build matvore's websocketd fork that fixed the --passenv for CGI scripts
# ----------------------------------
FROM golang:1.11.5-alpine AS build
RUN apk add git
WORKDIR /root
ENV CGO_ENABLED=0
RUN git clone https://github.com/matvore/websocketd \
    && cd websocketd \
    && go build \
    && ./websocketd --version

#
# --------------------
FROM alpine:$ALPINE_TAG
ARG CMARK_GFM_TAG

COPY --from=build /root/websocketd/websocketd /usr/local/bin/websocketd

COPY --from=cmark-gfm-build /usr/local/bin/cmark-gfm /usr/local/bin/
COPY --from=cmark-gfm-build /usr/local/lib/libcmark-gfm.so.$CMARK_GFM_TAG /usr/local/lib/
COPY --from=cmark-gfm-build /usr/local/lib/libcmark-gfm-extensions.so.$CMARK_GFM_TAG /usr/local/lib/
RUN cd /usr/local/lib \
    && ln -s libcmark-gfm.so.$CMARK_GFM_TAG libcmark-gfm.so \
    && ln -s libcmark-gfm-extensions.so.$CMARK_GFM_TAG libcmark-gfm-extensions.so \
    && cmark-gfm --version
COPY --from=cmark-gfm-build /usr/local/share/man/man1/cmark-gfm.1 /usr/local/share/man/man1/

RUN apk --no-cache add \
    bash \
    coreutils \
    jq \
    xmlstarlet
#
# NOTE: xmlstarlet is needed by the wiki app; also libxml2 in Alpine 3.21 appears
# to be broken, which makes xmlstarlet fail to read from STDIN.

RUN adduser -D -s /bin/bash baguette \
    && install -o baguette -g baguette -d /home/baguette/baguette

WORKDIR /home/baguette

USER baguette
ENV PATH=/home/baguette/baguette:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CMD ["/bin/bash"]
