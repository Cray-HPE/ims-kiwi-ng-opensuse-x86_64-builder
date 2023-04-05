#!/bin/sh
#
# MIT License
#
# (C) Copyright 2019, 2021-2022 Hewlett Packard Enterprise Development LP
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
set -x

echo on
RECIPE_ROOT_PARENT=${1:-/mnt/recipe}
IMAGE_ROOT_PARENT=${2:-/mnt/image}
PARAMETER_FILE_BUILD_FAILED=$IMAGE_ROOT_PARENT/build_failed
PARAMETER_FILE_KIWI_LOGFILE=$IMAGE_ROOT_PARENT/kiwi.log

# Make Cray's CA certificate a trusted system certificate within the container
# This will not install the CA certificate into the kiwi imageroot.
CA_CERT='/etc/cray/ca/certificate_authority.crt'
if [[ -e $CA_CERT ]]; then
	cp $CA_CERT  /usr/share/pki/trust/anchors/.
else
	echo "The CA certificate file: $CA_CERT is missing"
	exit 1
fi
update-ca-certificates
RC=$?
if [[ ! $RC ]]; then
	echo "update-ca-certificates exited with return code: $RC "
	exit 1
fi

echo "Setting ims job status to building_image"
python3 -m ims_python_helper image set_job_status $IMS_JOB_ID building_image

DEBUG_FLAGS=""
if [[ `echo $ENABLE_DEBUG | tr [:upper:] [:lower:]` = "true" ]]; then
    DEBUG_FLAGS="--debug"
fi

echo "Checking build platform: $BUILD_PLATFORM"
#if [ $BUILD_PLATFORM == "aarch64" ]; then
if false; then
    echo "Build platform is aarch64"
    # Regiser qemu-aarch64-static to act as an arm interpreter for arm builds 
    if [ ! -d /proc/sys/fs/binfmt_misc ] ; then
        echo "- binfmt_misc does not appear to be loaded or isn't built in."
        echo "  Trying to load it..."
        if ! modprobe binfmt_misc ; then
            echo "FATAL: Unable to load binfmt_misc"
            exit 1;
        fi
    fi

    # mount the filesystem
    if [ ! -f /proc/sys/fs/binfmt_misc/register ] ; then
        echo "- The binfmt_misc filesystem does not appear to be mounted."
        echo "  Trying to mount it..."
        if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
            echo "FATAL:  Unable to mount binfmt_misc filesystem."
            exit 1
        fi
    fi

    if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] ; then
        echo "- Removing old QEMU ARM64 setup."
        echo "-1" >> /proc/sys/fs/binfmt_misc/qemu-aarch64
    fi
    # register qemu for aarch64 images 
    echo "- Setting up QEMU for ARM64"
    echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OC" >> /proc/sys/fs/binfmt_misc/register

    # run the arm64 kiwi build
    podman pull --arch=arm64 docker://registry.local/artifactory.algol60.net/csm-docker/stable/$IMS_ARM_BUILDER
    podman run  --privileged --arch=arm64 --entrypoint "/scripts/armentry.sh" -e BUILD_PLATFORM=$BUILD_PLATFORM -v /mnt/recipe/:/mnt/recipe -v /mnt/image:/mnt/image -v /etc/cray/ca/:/etc/cray/ca/ -v /mnt/ca-rpm/:/mnt/ca-rpm  docker://registry.local/artifactory.algol60.net/csm-docker/stable/$IMS_ARM_BUILDER
    exit 0
fi

# Call kiwi to build the image recipe. Note that the command line --add-bootstrap-package
# causes kiwi to install the cray-ca-cert rpm into the image root.

echo "Calling kiwi-ng build..."
#    --target-arch=$BUILD_PLATFORM \
kiwi-ng \
    $DEBUG_FLAGS \
    --logfile=$PARAMETER_FILE_KIWI_LOGFILE \
    --type tbz system build \
    --description $RECIPE_ROOT_PARENT \
    --target $IMAGE_ROOT_PARENT \
    --add-bootstrap-package file:///mnt/ca-rpm/cray_ca_cert-1.0.1-1.x86_64.rpm \
    --signing-key /signing-keys/HPE-SHASTA-RPM-PROD.asc \
    --signing-key /signing-keys/SUSE-gpg-pubkey-39db7c82-5f68629b.asc
rc=$?

if [ "$rc" -ne "0" ]; then
  echo "ERROR: Kiwi reported a build error."
  touch $PARAMETER_FILE_BUILD_FAILED
fi

# Always return 0
exit 0
