#!/usr/bin/env sh

: ${MEGA_DIRECTORY:=/}
: ${MEGA_EMAIL}
: ${MEGA_PASSWORD}
: ${MEGA_SCALE:=2}
: ${MEGA_STREAM_LIMIT:=4}
: ${MEGA_TRANSFER_LIMIT:=3}
: ${RCLONE_BUFFER_SIZE:=64}
: ${RCLONE_CHUNK_SIZE:=64}
: ${RCLONE_STREAM_LIMIT:="$(( $MEGA_STREAM_LIMIT * $MEGA_SCALE ))"}
: ${RCLONE_TRANSFER_LIMIT:="$(( $MEGA_TRANSFER_LIMIT * $MEGA_SCALE ))"}
: ${RCLONE_VFS_CACHE_MAX_SIZE:="$(( $MEGA_STREAM_LIMIT * $RCLONE_CHUNK_SIZE * 2 + $MEGA_TRANSFER_LIMIT * $RCLONE_CHUNK_SIZE ))"}
: ${RCLONE_VFS_READ_AHEAD:="$(( $RCLONE_CHUNK_SIZE * 2 ))"}
: ${RCLONE_VFS_READ_CHUNK_SIZE:=16}
: ${RCLONE_VFS_READ_CHUNK_SIZE_LIMIT:=64}

iptables-save | iptables-restore-translate -f /dev/stdin > /etc/nftables.d/docker.nft
iptables -F; iptables -X; iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
apk del iptables

mkdir -p \
    /etc/mega \
    /etc/rclone \
    /run/openrc

chmod +x \
    /entrypoint.sh \
    /etc/init.d/mega \
    /etc/init.d/rclone

cat << EOF >> /etc/mega/.env
DIRECTORY="$MEGA_DIRECTORY"
EMAIL="$MEGA_EMAIL"
PASSWORD="$MEGA_PASSWORD"
STREAM_LIMIT="$MEGA_STREAM_LIMIT"
TRANSFER_LIMIT="$MEGA_TRANSFER_LIMIT"
EOF

cat << EOF >> /etc/rclone/.env
BUFFER_SIZE="$RCLONE_BUFFER_SIZE"
CHUNK_SIZE="$RCLONE_CHUNK_SIZE"
STREAM_LIMIT="$RCLONE_STREAM_LIMIT"
TRANSFER_LIMIT="$RCLONE_TRANSFER_LIMIT"
VFS_CACHE_MAX_SIZE="$RCLONE_VFS_CACHE_MAX_SIZE"
VFS_READ_AHEAD="$RCLONE_VFS_READ_AHEAD"
VFS_READ_CHUNK_SIZE="$RCLONE_VFS_READ_CHUNK_SIZE"
VFS_READ_CHUNK_SIZE_LIMIT="$RCLONE_VFS_READ_CHUNK_SIZE_LIMIT"
EOF

ID=0
REMOTES=""
while [ "$ID" -lt "$MEGA_SCALE" ] && [ "$ID" -lt 8 ]; do
cat << EOF >> /etc/rclone/rclone.conf
[mega-${ID}]
type = webdav
vendor = other
url = #mega-${ID}-url
EOF
    cp "/etc/init.d/mega" "/etc/init.d/mega-${ID}"
    rc-update add "mega-${ID}"
    REMOTES="${REMOTES}mega-${ID}: "
    ID=$(($ID + 1))
done
rm /etc/init.d/mega

if [ "$MEGA_SCALE" -gt 1 ]; then
cat << EOF >> /etc/rclone/rclone.conf
[remote]
type = union
upstreams = ${REMOTES}
action_policy = eprand
create_policy = eprand
search_policy = epff
EOF
else
    sed -i "s|\[mega-0\]|\[remote\]|" /etc/rclone/rclone.conf
fi

if [ "$RCLONE_CHUNKER_ENABLED" = true ]; then
cat << EOF >> /etc/rclone/rclone.conf
[default]
type = chunker
remote = remote:
chunk_size = ${RCLONE_CHUNK_SIZE}M
hash_type = sha1all
name_format = *.chunk.#
EOF
else
    sed -i "s|\[remote\]|\[default\]|" /etc/rclone/rclone.conf
fi

rc-update add nfs
rc-update add nftables
rc-update add rclone

sed -i 's/^tty/#&/' /etc/inittab
touch /run/openrc/softlevel

exec /sbin/init
