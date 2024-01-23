#!/usr/bin/env sh

: ${SANDBOX_PATH:="/chroot/${RC_SVCNAME}"}
: ${SANDBOX_NAME:="$RC_SVCNAME"}
: ${SANDBOX_NUMBER:="${RC_SVCNAME##*-}"}

[ -n "$SANDBOX_NAME" ] && [ -c "${SANDBOX_PATH}/dev/urandom" ] || {
    FORWARD_SANDBOX_PORT="1000${SANDBOX_NUMBER}"
    HOST_VETH="mega${SANDBOX_NUMBER}"
    PEER_VETH="veth${SANDBOX_NUMBER}"

    mkdir -p \
        "${SANDBOX_PATH}/dev" \
        "${SANDBOX_PATH}/home" \
        "${SANDBOX_PATH}/tmp"

    chown nobody \
        "${SANDBOX_PATH}/home" \
        "${SANDBOX_PATH}/tmp"

    mknod -m 0666 "${SANDBOX_PATH}/dev/null" c 1 3
    mknod -m 0666 "${SANDBOX_PATH}/dev/urandom" c 1 9

    # Create a network namespace
    ip netns add "$SANDBOX_NAME"

    # Create a veth pair with specified names
    ip link add "$HOST_VETH" type veth peer name "$PEER_VETH"

    # Move one end into the network namespace
    ip link set "$PEER_VETH" netns "$SANDBOX_NAME"

    # Set up the loopback interface within the namespace
    ip netns exec "$SANDBOX_NAME" ip link set lo up

    # Rename the veth interface to eth0 inside the namespace
    ip netns exec "$SANDBOX_NAME" ip link set "$PEER_VETH" name eth0

    # Assign IP addresses within the namespace
    ip addr add "10.0.${SANDBOX_NUMBER}.1/30" dev "$HOST_VETH"
    ip netns exec "$SANDBOX_NAME" ip addr add "10.0.${SANDBOX_NUMBER}.2/30" dev eth0

    # Bring up the veth interfaces
    ip link set "$HOST_VETH" up
    ip netns exec "$SANDBOX_NAME" ip link set eth0 up

    # Set the default route within the namespace
    ip netns exec "$SANDBOX_NAME" ip route add default via "10.0.${SANDBOX_NUMBER}.1"

    # Create the NAT table
    nft add table inet nat

    # Enable IP masquerading on the host for traffic from the namespace
    nft add chain inet nat postrouting \{ type nat hook postrouting priority 0 \; \}
    nft add rule inet nat postrouting masquerade

    # Redirect locally generated traffic to the namespace
    nft add chain inet nat output \{ type nat hook output priority 0 \; \}
    nft add rule inet nat output ip daddr 127.0.0.1 tcp dport "$FORWARD_SANDBOX_PORT" dnat to "10.0.${SANDBOX_NUMBER}.2:${FORWARD_SANDBOX_PORT}"
}

sandbox() {
    CMD="$@"

    ip netns exec ${SANDBOX_NAME} su -s /bin/sh -c " \
        HOME=/home \
        unshare -r \
        chroot ${SANDBOX_PATH} \
        ${CMD}
    " nobody
}
