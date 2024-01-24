ARG ALPINE_VERSION=3.19
ARG CRYPTOPP_VERSION=8.9.0
ARG MEGA_CMD_VERSION=1.6.3
ARG MEGA_SDK_VERSION=4.17.1d
ARG RCLONE_VERSION=1.65.1

FROM alpine:${ALPINE_VERSION} as mega

ARG CRYPTOPP_VERSION
ARG MEGA_CMD_VERSION
ARG MEGA_SDK_VERSION

RUN apk add --virtual .build-deps \
        autoconf \
        automake \
        c-ares-dev \
        c-ares-static \
        crypto++-dev \
        curl \
        curl-dev \
        curl-static \
        freeimage-dev \
        g++ \
        icu-dev \
        icu-static \
        libsodium-dev \
        libsodium-static \
        libtool \
        libuv-dev \
        libuv-static \
        linux-headers \
        make \
        openssl-dev \
        openssl-libs-static \
        readline-dev \
        readline-static \
        sqlite-dev \
        sqlite-static \
        zlib-dev \
        zlib-static

WORKDIR /build/cryptopp

RUN curl -fsSL "https://cryptopp.com/cryptopp${CRYPTOPP_VERSION//./}.zip" \
    | unzip -d . - \
    && g++ -DNDEBUG -g3 -O2 -march=native -pipe -c *.cpp \
    ; ar rcs libcryptopp.a *.o \
    && mv libcryptopp.a /usr/local/lib/

WORKDIR /build/mega

RUN curl -fsSL https://github.com/meganz/MEGAcmd/archive/refs/tags/${MEGA_CMD_VERSION}_Linux/MEGAcmd-${MEGA_CMD_VERSION}.tar.gz \
    | tar -xz --strip-components=1 \
    && curl -fsSL https://github.com/meganz/sdk/archive/refs/tags/v${MEGA_SDK_VERSION}/sdk-v${MEGA_SDK_VERSION}.tar.gz \
    | tar -xzC ./sdk --strip-components=1 \
    && sed -i 's|/bin/bash|/bin/sh|' ./src/client/mega-* \
    && CXXFLAGS="-flto=auto -fpermissive -static-libgcc -static-libstdc++" \
    && ./autogen.sh \
    && ./configure \
        CXXFLAGS="${CXXFLAGS}" \
        --build=$CBUILD \
        --host=$CHOST \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --prefix=/usr \
        --sysconfdir=/etc \
        --disable-examples \
        --disable-shared \
    && make -j $(nproc) \
    && make install

FROM rclone/rclone:${RCLONE_VERSION} as rclone

FROM alpine:${ALPINE_VERSION}

RUN apk add \
        c-ares \
        conntrack-tools \
        crypto++ \
        freeimage \
        fuse3 \
        iproute2 \
        iptables \
        libcurl \
        libgcc \
        libsodium \
        libstdc++ \
        libuv \
        nfs-utils \
        nfs-utils-openrc \
        nftables \
        nftables-openrc \
        openrc \
        sqlite-libs

COPY --from=mega /usr/bin/mega-cmd-server /usr/bin/
COPY --from=mega /usr/bin/mega-exec /usr/bin/
COPY --from=mega /usr/bin/mega-login /usr/bin/
COPY --from=mega /usr/bin/mega-webdav /usr/bin/
COPY --from=rclone /usr/local/bin/rclone /usr/bin/

ADD rootfs /

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 2049/tcp

VOLUME /var/rclone

HEALTHCHECK CMD rc-status -C sysinit | awk 'NR>1 && !(/started/) {exit 1}'
