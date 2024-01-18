#!/usr/bin/env sh

: ${BUFFER_SIZE:=64}
: ${CHUNK_SIZE:=64}
: ${DIRECTORY:=/}
: ${READ_CHUNK_SIZE:=16}
: ${READ_CHUNK_SIZE_LIMIT:=128}
: ${STREAMS:=1}
: ${TRANSFERS:=1}

mkdir -p \
    /etc/mega \
    /etc/rclone \
    /run/openrc

chmod +x \
    /entrypoint.sh \
    /etc/init.d/mega \
    /etc/init.d/rclone

cat << EOF >> /etc/mega/.env
EMAIL="$EMAIL"
PASSWORD="$PASSWORD"
DIRECTORY="$DIRECTORY"
EOF

cat << EOF >> /etc/rclone/.env
CHUNK_SIZE="$CHUNK_SIZE"
READ_CHUNK_SIZE="$READ_CHUNK_SIZE"
STREAMS="$STREAMS"
TRANSFERS="$TRANSFERS"
BUFFER_SIZE="$BUFFER_SIZE"
EOF

ID=0
REMOTES=""
while [ "$ID" -lt "$TRANSFERS" ] && [ "$ID" -lt 8 ]; do
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

if [ "$TRANSFERS" -gt 1 ]; then
cat << EOF >> /etc/rclone/rclone.conf
[default]
type = union
upstreams = ${REMOTES}
action_policy = eprand
create_policy = eprand
search_policy = epff
EOF
else
    sed -i "s|\[mega-0\]|\[default\]|" /etc/rclone/rclone.conf
fi

rc-update add nfs
rc-update add rclone

touch /run/openrc/softlevel

sed -i 's/^tty/#&/' /etc/inittab

exec /sbin/init
