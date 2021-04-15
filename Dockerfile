## Cray Image Management Service image build environment Dockerfile
# Copyright 2018, 2021, Hewlett Packard Enterprise Development LP
FROM arti.dev.cray.com/baseos-docker-master-local/opensuse-leap:15.2

COPY requirements.txt constraints.txt /
RUN zypper in -y python3-pip python3-kiwi yum xz jing && \
    zypper clean && \
    pip install --upgrade pip \
        --trusted-host dst.us.cray.com \
        --index-url http://dst.us.cray.com/piprepo/simple && \
    pip install \
       --no-cache-dir \
       -r requirements.txt

VOLUME /mnt/image
VOLUME /mnt/recipe

RUN mkdir -p /scripts
COPY entrypoint.sh /scripts/entrypoint.sh
ENTRYPOINT ["/scripts/entrypoint.sh"]


