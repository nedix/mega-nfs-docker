#!/usr/bin/env sh

: ${SERVICE_NAME:="$RC_SVCNAME"}
: ${SERVICE_ID:="${RC_SVCNAME##*-}"}
: ${CHROOT_PATH:="/chroot/${RC_SVCNAME}"}

[ ! -d "$CHROOT_PATH" ] \
&& [ -n "$CHROOT_PATH" ] \
&& [ -n "$SERVICE_ID" ] \
&& {
    HOST_VETH="mega${SERVICE_ID}"
    SERVICE_PORT="1000${SERVICE_ID}"
    PEER_VETH="veth${SERVICE_ID}"

    mkdir -p \
        "${CHROOT_PATH}/dev" \
        "${CHROOT_PATH}/home" \
        "${CHROOT_PATH}/tmp"

    chown nobody \
        "${CHROOT_PATH}/home" \
        "${CHROOT_PATH}/tmp"

    mknod -m 0666 "${CHROOT_PATH}/dev/null" c 1 3
    mknod -m 0666 "${CHROOT_PATH}/dev/urandom" c 1 9

    # Create a network namespace
    ip netns add "$SERVICE_NAME"

    # Create a veth pair with specified names
    ip link add "$HOST_VETH" type veth peer name "$PEER_VETH"

    # Move one end into the network namespace
    ip link set "$PEER_VETH" netns "$SERVICE_NAME"

    # Set up the loopback interface within the namespace
    ip netns exec "$SERVICE_NAME" ip link set lo up

    # Rename the veth interface to eth0 inside the namespace
    ip netns exec "$SERVICE_NAME" ip link set "$PEER_VETH" name eth0

    # Assign IP addresses within the namespace
    ip addr add "10.0.${SERVICE_ID}.1/30" dev "$HOST_VETH"
    ip netns exec "$SERVICE_NAME" ip addr add "10.0.${SERVICE_ID}.2/30" dev eth0

    # Bring up the veth interfaces
    ip link set "$HOST_VETH" up
    ip netns exec "$SERVICE_NAME" ip link set eth0 up

    # Set the default route within the namespace
    ip netns exec "$SERVICE_NAME" ip route add default via "10.0.${SERVICE_ID}.1"

    # Create the NAT table
    nft add table inet nat

    # Enable IP masquerading on the host for traffic from the namespace
    nft add chain inet nat postrouting \{ type nat hook postrouting priority 0 \; \}
    nft add rule inet nat postrouting masquerade

    # Redirect locally generated traffic to the namespace
    nft add chain inet nat output \{ type nat hook output priority 0 \; \}
    nft add rule inet nat output ip daddr 127.0.0.1 tcp dport "$SERVICE_PORT" dnat to "10.0.${SERVICE_ID}.2:${SERVICE_PORT}"
}

jail() {
    CMD="$@"

    su -s /bin/sh -c " \
        HOME=/home \
        unshare -r \
        chroot ${CHROOT_PATH} \
        ${CMD}
    " nobody
}

firewall() {
    CMD="$@"

    ip netns exec ${SERVICE_NAME} su -s /bin/sh -c " \
        HOME=/home \
        unshare -r \
        chroot ${CHROOT_PATH} \
        ${CMD}
    " nobody
}
