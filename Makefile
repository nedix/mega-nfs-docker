setup:
	@docker build . -t mega-nfs

up: port = 2049
up:
	@docker run --rm --name mega-nfs \
        --cap-add SYS_ADMIN \
        --device /dev/fuse \
        -v /sys/fs/cgroup/mega-nfs:/sys/fs/cgroup:rw \
        --env-file .env \
        -p $(port):2049 \
        -d \
        mega-nfs

down:
	-@docker stop mega-nfs

shell:
	@docker exec -it mega-nfs /bin/sh
