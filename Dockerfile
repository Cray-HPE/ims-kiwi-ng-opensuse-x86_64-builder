#
# MIT License
#
# (C) Copyright 2018, 2021-2024 Hewlett Packard Enterprise Development LP
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
FROM artifactory.algol60.net/csm-docker/stable/docker.io/opensuse/leap:15.6 as base

COPY requirements.txt constraints.txt zypper-refresh-patch-clean.sh /
# 1. Install qemu-aarch64-static binary to handle arm64 emulation if needed
# 2. Update xalan-j2 package to avoid CVE. Currently we have to add a repo to get it.
# 3. Apply security patches
# 4. Install Python
RUN --mount=type=secret,id=netrc,target=/root/.netrc \
    zypper in -y python3-pip python3-kiwi xz jing curl podman kmod make wget openssh squashfs vi gzip && \
    wget https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static && \
    mv ./qemu-aarch64-static /usr/bin/qemu-aarch64-static && \
    chmod +x /usr/bin/qemu-aarch64-static && \
    zypper --non-interactive ar http://download.opensuse.org/tumbleweed/repo/oss/ tumbleweed && \
    zypper --non-interactive refresh && \
    zypper --non-interactive in -y 'xalan-j2>=2.7.3' && \
    zypper --non-interactive rr tumbleweed && \
    /zypper-refresh-patch-clean.sh && \
    rm /zypper-refresh-patch-clean.sh && \
    pip3 install --upgrade pip && \
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 list --format freeze

VOLUME /mnt/image

RUN mkdir -p /scripts /signing-keys /mnt/image/recipe
COPY signing-keys/HPE-SHASTA-RPM-PROD.asc /signing-keys
COPY signing-keys/HPE-SHASTA-RPM-PROD-FIPS.public /signing-keys
COPY signing-keys/SUSE-gpg-pubkey-39db7c82-5f68629b.asc /signing-keys
COPY scripts/. /scripts
COPY Dockerfile.remote /Dockerfile.remote
ENTRYPOINT ["/scripts/entrypoint.sh"]
