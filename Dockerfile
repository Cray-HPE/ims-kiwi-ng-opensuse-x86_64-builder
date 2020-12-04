## Cray Image Management Service image build environment Dockerfile
## Copyright 2018, Cray Inc. All rights reserved.
FROM dtr.dev.cray.com/baseos/opensuse:15

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


