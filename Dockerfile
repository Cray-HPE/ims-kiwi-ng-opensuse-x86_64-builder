#
# MIT License
#
# (C) Copyright 2018, 2021-2023 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# Cray Image Management Service image build environment Dockerfile
#FROM arti.hpc.amslabs.hpecorp.net/baseos-docker-master-local/opensuse-leap:15.2 as base
FROM opensuse/leap:15.4 as base

COPY requirements.txt constraints.txt /

RUN zypper in -y python3-pip python3-kiwi xz jing curl podman kmod make

RUN curl -o qemu-aarch64-static https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static  \
&& mv ./qemu-aarch64-static /usr/bin/qemu-aarch64-static && chmod +x /usr/bin/qemu-aarch64-static

# Apply security patches
COPY zypper-refresh-patch-clean.sh /
RUN /zypper-refresh-patch-clean.sh && rm /zypper-refresh-patch-clean.sh

RUN pip3 install --upgrade pip
RUN --mount=type=secret,id=netrc,target=/root/.netrc \
    pip3 install --no-cache-dir -r requirements.txt

VOLUME /mnt/image
VOLUME /mnt/recipe

RUN mkdir -p /scripts /signing-keys
COPY signing-keys/HPE-SHASTA-RPM-PROD.asc /signing-keys
COPY signing-keys/SUSE-gpg-pubkey-39db7c82-5f68629b.asc /signing-keys
COPY entrypoint.sh /scripts/entrypoint.sh
COPY armentry.sh /scripts/armentry.sh
ENTRYPOINT ["/scripts/entrypoint.sh"]
