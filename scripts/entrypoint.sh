#!/bin/sh
#
# MIT License
#
# (C) Copyright 2019, 2021-2023 Hewlett Packard Enterprise Development LP
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

# NOTE: this script is run in the k8s IMS job. It will either run the native
#  build locally, spawn off a remote build, or run an aarch64 emulation build.

echo on
RECIPE_ROOT_PARENT=${1:-/mnt/image/recipe}
IMAGE_ROOT_PARENT=${2:-/mnt/image}
PARAMETER_FILE_BUILD_FAILED=$IMAGE_ROOT_PARENT/build_failed
PARAMETER_FILE_KIWI_LOGFILE=$IMAGE_ROOT_PARENT/kiwi.log

function run_emulation_build() {
    echo "Build architecture is $BUILD_ARCH - running under emulation"
    # Regiser qemu-aarch64-static to act as an arm interpreter for arm builds 
    if [ ! -d /proc/sys/fs/binfmt_misc ] ; then
        echo "- binfmt_misc does not appear to be loaded or isn't built in."
        echo "  Trying to load it..."
        if ! modprobe binfmt_misc ; then
            echo "FATAL: Unable to load binfmt_misc"
            exit 1;
        fi
    fi

    # mount the emulation filesystem
    if [ ! -f /proc/sys/fs/binfmt_misc/register ] ; then
        echo "- The binfmt_misc filesystem does not appear to be mounted."
        echo "  Trying to mount it..."
        if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
            echo "FATAL:  Unable to mount binfmt_misc filesystem."
            exit 1
        fi
    fi

    # register qemu for aarch64 images 
    if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] ; then
        echo "- Setting up QEMU for ARM64"
        echo ":qemu-aarch64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" >> /proc/sys/fs/binfmt_misc/register
    fi

    # Remove podman references to overlayfs to utilize vfs instead
    rm -rf /var/lib/containers/

    # run the arm64 kiwi build inside this new pod
    podman --storage-driver=vfs pull --platform linux/arm64 docker://registry.local/$IMS_ARM_BUILDER
    podman --storage-driver=vfs run  --privileged --platform linux/arm64 --entrypoint "/scripts/armentry.sh" -e BUILD_ARCH=$BUILD_ARCH -v /signing-keys:/signing-keys -v /mnt/image/recipe/:/mnt/image/recipe -v /mnt/image:/mnt/image -v /etc/cray/ca/:/etc/cray/ca/ -v /mnt/ca-rpm/:/mnt/ca-rpm  docker://registry.local/$IMS_ARM_BUILDER
}

function run_remote_build() {
    echo "Running remote build on host: $REMOTE_BUILD_NODE"

    # load up env file for image
    echo export OAUTH_CONFIG_DIR=${OAUTH_CONFIG_DIR} > /env.sh
    echo BUILD_ARCH=${BUILD_ARCH} >> /env.sh
    echo IMS_JOB_ID=${IMS_JOB_ID} >> /env.sh
    echo IMAGE_ROOT_PARENT=${IMAGE_ROOT_PARENT} >> /env.sh
    echo RECIPE_ROOT_PARENT=/data/recipe >> env.sh

    # Modify the dockerfile to use the correct base image
    (echo "cat <<EOF" ; cat Dockerfile.remote ; echo EOF ) | sh > Dockerfile

    # build the docker image
    podman build -t ims-remote-${IMS_JOB_ID}:1.0.0 .

    # Copy docker image to remote node
    podman save ims-remote-${IMS_JOB_ID}:1.0.0 | ssh root@${REMOTE_BUILD_NODE} podman load

    # remote run of the docker image
    ## NOTE: do not use '-rm' tag as we want access to the results
    ssh root@${REMOTE_BUILD_NODE} "podman run --name ims-${IMS_JOB_ID} --privileged -t -i ims-remote-${IMS_JOB_ID}:1.0.0"

    # check the results of the build
    ssh root@${REMOTE_BUILD_NODE} "podman cp ims-${IMS_JOB_ID}:${IMAGE_ROOT_PARENT}/build_failed /tmp"
    rc=$?
    if [ "$rc" -ne "0" ]; then
        # Failed rc indicates file not present
        echo "ERROR: Kiwi reported a build error."
        touch $PARAMETER_FILE_BUILD_FAILED
    else
        # copy image files from pod to remote machine
        ## NOTE - need to copy to /tmp - VERY limited for space...
        ssh root@${REMOTE_BUILD_NODE} "mkdir -p /tmp/${IMS_JOB_ID}/"
        ssh root@${REMOTE_BUILD_NODE} "podman cp ims-${IMS_JOB_ID}:${IMAGE_ROOT_PARENT}/transfer.sqsh /tmp/${IMS_JOB_ID}/"
        ssh root@${REMOTE_BUILD_NODE} "podman cp ims-${IMS_JOB_ID}:${IMAGE_ROOT_PARENT}/kiwi.log /tmp/${IMS_JOB_ID}/"

        # copy image files from remote machine to job pod
        scp root@${REMOTE_BUILD_NODE}:/tmp/${IMS_JOB_ID}/* ${IMAGE_ROOT_PARENT}

        # delete build files from remote host
        ssh root@${REMOTE_BUILD_NODE} "rm -rf /tmp/${IMS_JOB_ID}/"

        # unpack squashfs
        mkdir -p ${IMAGE_ROOT_PARENT}/build
        unsquashfs -f -d ${IMAGE_ROOT_PARENT}/build/image-root ${IMAGE_ROOT_PARENT}/transfer.sqsh
        rm ${IMAGE_ROOT_PARENT}/transfer.sqsh
        touch $PARAMETER_FILE_BUILD_SUCCEEDED
    fi

    # delete artifacts off of remote host
    # NOTE: need to prune the anonymous volume explicitly to free up the space
    ssh root@${REMOTE_BUILD_NODE} "rm -rf /tmp/${IMS_JOB_ID}/"
    ssh root@${REMOTE_BUILD_NODE} "podman rm ims-${IMS_JOB_ID}"
    ssh root@${REMOTE_BUILD_NODE} "podman rmi ims-remote-${IMS_JOB_ID}:1.0.0"
    ssh root@${REMOTE_BUILD_NODE} "podman volume prune -f"
}

function run_local_build() {
    # Call kiwi to build the image recipe. Note that the command line --add-bootstrap-package
    # causes kiwi to install the cray-ca-cert rpm into the image root.
    echo "Calling kiwi-ng build..."
    kiwi-ng \
        $DEBUG_FLAGS \
        --logfile=$PARAMETER_FILE_KIWI_LOGFILE \
        --type tbz system build \
        --description $RECIPE_ROOT_PARENT \
        --target $IMAGE_ROOT_PARENT \
        --add-bootstrap-package file:///mnt/ca-rpm/cray_ca_cert-1.0.1-1.noarch.rpm \
        --signing-key /signing-keys/HPE-SHASTA-RPM-PROD.asc \
        --signing-key /signing-keys/SUSE-gpg-pubkey-39db7c82-5f68629b.asc
    rc=$?

    if [ "$rc" -ne "0" ]; then
        echo "ERROR: Kiwi reported a build error."
        touch $PARAMETER_FILE_BUILD_FAILED
    fi
}

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

# If this is running on a remote builder node, set up and control
# the build from here
if [[ ! -z "$REMOTE_BUILD_NODE" ]]; then
    # TODO - must get correct ssh private key here
    run_remote_build
elif [ "$BUILD_ARCH" == "aarch64" ]; then
    run_emulation_build
else
    run_local_build
fi

# Always return 0
exit 0
