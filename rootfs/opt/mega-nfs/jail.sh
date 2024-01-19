#!/usr/bin/env sh

[ -z "$NAME" ] && NAME=$(basename "${1##.*}")

[ -d "/chroot/${NAME}" ] || {
    mkdir -p \
        "/chroot/${NAME}/dev" \
        "/chroot/${NAME}/home" \
        "/chroot/${NAME}/tmp"

    chown nobody \
        "/chroot/${NAME}/home" \
        "/chroot/${NAME}/tmp"

    mknod -m 0666 "/chroot/${NAME}/dev/null" c 1 3
    mknod -m 0666 "/chroot/${NAME}/dev/urandom" c 1 9
}

jail() {
    CMD="$@"

    su -s /bin/sh -c " \
        HOME=/home \
        unshare -r \
        chroot /chroot/${NAME} \
        ${CMD}
    " nobody
}
