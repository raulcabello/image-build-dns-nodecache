ARG UBI_IMAGE=registry.access.redhat.com/ubi7/ubi-minimal:latest
ARG GO_IMAGE=rancher/hardened-build-base:v1.16.7b7
# We need iptables and ip6tables. We will get them from the hardened kube-proxy image
ARG KUBE_PROXY_IMAGE=rancher/hardened-kube-proxy:v1.21.3-build20210716

ARG TAG="1.19.1"
ARG ARCH="amd64"
FROM ${UBI_IMAGE} as ubi
FROM ${KUBE_PROXY_IMAGE} as kube-proxy
FROM ${GO_IMAGE} as base-builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    git \
    make

# setup the dnsNodeCache build
FROM base-builder as dnsNodeCache-builder
ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
ARG TAG
ARG ARCH
WORKDIR $GOPATH/src/${PKG}
RUN git tag --list
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GOARCH=${ARCH} GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN go-assert-boring.sh node-cache
RUN install -s node-cache /usr/local/bin

FROM ubi as dnsNodeCache
RUN microdnf update -y && \
    microdnf install nc which && \
    rm -rf /var/cache/yum
COPY --from=dnsNodeCache-builder /usr/local/bin/node-cache /node-cache
COPY --from=kube-proxy /usr/sbin/ip* /usr/sbin/
COPY --from=kube-proxy /usr/sbin/xtables* /usr/sbin/
ENTRYPOINT ["/node-cache"]
