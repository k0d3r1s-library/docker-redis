FROM k0d3r1s/alpine:unstable as builder

USER root

ENV REDIS_VERSION master

COPY ./redis/ /usr/src/redis 
COPY docker-entrypoint.sh /usr/local/bin/

RUN \
	set -eux \
&&	apk upgrade --no-cache --available \
&&	apk add --update --no-cache --upgrade -X http://dl-cdn.alpinelinux.org/alpine/edge/testing --virtual .build-deps coreutils dpkg-dev dpkg gcc linux-headers make musl-dev openssl-dev \
&&	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' /usr/src/redis/src/config.c \
&&	sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' /usr/src/redis/src/config.c \
&&	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' /usr/src/redis/src/config.c \
&&	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
&&	extraJemallocConfigureFlags="--build=$gnuArch" \
&&	dpkgArch="$(dpkg --print-architecture)" \
&&	case "${dpkgArch##*-}" in \
		amd64 | i386 | x32) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=12" ;; \
		*) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=16" ;; \
	esac \
&&	extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-hugepage=21" \
&&	grep -F 'cd jemalloc && ./configure ' /usr/src/redis/deps/Makefile \
&&	sed -ri 's!cd jemalloc && ./configure !&'"$extraJemallocConfigureFlags"' !' /usr/src/redis/deps/Makefile \
&&	grep -F "cd jemalloc && ./configure $extraJemallocConfigureFlags " /usr/src/redis/deps/Makefile \
&&	export BUILD_TLS=no \
&&	make -C /usr/src/redis -j "$(expr $(nproc) / 3)" CFLAGS="-DUSE_PROCESSOR_CLOCK" all \
&&	make -C /usr/src/redis install \
&&	serverMd5="$(md5sum /usr/local/bin/redis-server | cut -d' ' -f1)"; export serverMd5 \
&&	find /usr/local/bin/redis* -maxdepth 0 \
		-type f -not -name redis-server \
		-exec sh -eux -c ' \
			md5="$(md5sum "$1" | cut -d" " -f1)"; \
			test "$md5" = "$serverMd5"; \
		' -- '{}' ';' \
		-exec ln -svfT 'redis-server' '{}' ';' \
	 \
&&	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
&&	apk add --no-network --no-cache --virtual .redis-rundeps $runDeps \
&&	apk del --no-network --purge --no-cache .build-deps liburing-dev \
&&	sed -i 's/^\(daemonize .*\)$/# \1/' /usr/src/redis/redis.conf \
&&	sed -i 's/^\(dir .*\)$/# \1\ndir \/data/' /usr/src/redis/redis.conf \
&&	sed -i 's/^\(logfile .*\)$/# \1/' /usr/src/redis/redis.conf \
&&	sed -i 's/protected-mode yes/protected-mode no/g' /usr/src/redis/redis.conf \
&&	sed -i 's/# save ""/save ""/g' /usr/src/redis/redis.conf \
&&	sed -i 's/save 900 1/# save 900 1/g' /usr/src/redis/redis.conf \
&&	sed -i 's/save 300 10/# save 300 10/g' /usr/src/redis/redis.conf \
&&	sed -i 's/save 60 10000/# save 60 10000/g' /usr/src/redis/redis.conf \
&&	sed -i 's/stop-writes-on-bgsave-error yes/stop-writes-on-bgsave-error no/g' /usr/src/redis/redis.conf \
&&	sed -i 's/bind 127.0.0.1 -::1/bind 0.0.0.0/g' /usr/src/redis/redis.conf \
&&  cp /usr/src/redis/redis.conf /etc/redis.conf \
&&	mkdir /data && chown vairogs:vairogs /data \
&&  rm -rf \
		/var/cache/* \
		/tmp/* \
		/usr/share/man \
		/usr/src/redis \
&&	chmod +x /usr/local/bin/docker-entrypoint.sh

FROM scratch

COPY --from=builder / /

ENV REDIS_VERSION master
WORKDIR /data

ENTRYPOINT ["docker-entrypoint.sh"]

USER vairogs

EXPOSE 6379

CMD ["redis-server", "/etc/redis.conf"]
