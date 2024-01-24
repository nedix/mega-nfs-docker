#!/usr/bin/env sh

: ${MEGA_DIRECTORY:=/}
: ${MEGA_INSTANCES:=2}
: ${MEGA_STREAMS:=4}
: ${MEGA_TRANSFERS:=3}
: ${RCLONE_BUFFER_SIZE:=64}
: ${RCLONE_CHUNK_SIZE:=64}
: ${RCLONE_READ_CHUNK_SIZE:=16}
: ${RCLONE_READ_CHUNK_SIZE_LIMIT:=128}

mkdir -p \
    /etc/mega \
    /etc/rclone \
    /run/openrc

chmod +x \
    /entrypoint.sh \
    /etc/init.d/mega \
    /etc/init.d/rclone

cat << EOF >> /etc/mega/.env
EMAIL="$MEGA_EMAIL"
PASSWORD="$MEGA_PASSWORD"
DIRECTORY="$MEGA_DIRECTORY"
STREAMS="$MEGA_STREAMS"
TRANSFERS="$MEGA_TRANSFERS"
EOF

cat << EOF >> /etc/rclone/.env
BUFFER_SIZE="$RCLONE_BUFFER_SIZE"
CHUNK_SIZE="$RCLONE_CHUNK_SIZE"
READ_CHUNK_SIZE="$RCLONE_READ_CHUNK_SIZE"
STREAMS="$(( $MEGA_STREAMS * $MEGA_INSTANCES ))"
TRANSFERS="$(( $MEGA_TRANSFERS * $MEGA_INSTANCES ))"
EOF

ID=0
REMOTES=""
while [ "$ID" -lt "$MEGA_INSTANCES" ] && [ "$ID" -lt 8 ]; do
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

if [ "$MEGA_INSTANCES" -gt 1 ]; then
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
