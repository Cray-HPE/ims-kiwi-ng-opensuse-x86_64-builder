#!/bin/sh
#
# MIT License
#
# (C) Copyright 2019, 2021-2025 Hewlett Packard Enterprise Development LP
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
SSH_CONNECTION_TIMEOUT_SECONDS=300
SSH_SERVER_ALIVE_INTERVAL_SECONDS=10
SSH_SERVER_ALIVE_COUNT=30


function run_emulation_build() {
    echo "Build architecture is $BUILD_ARCH - running under emulation"
    # Register qemu-aarch64-static to act as an arm interpreter for arm builds 
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

    # The dockerfile expects a dir at `/etc/cray/signing-keys` which should be a mounted secret
    # If the dir does not exist, create it
    if [ ! -d /etc/cray/signing-keys ]; then
        echo "Creating /etc/cray/signing-keys directory"
        mkdir -p /etc/cray/signing-keys
    fi

    # NOTE: if we can get --cpu-rt-runtime=950000 to work in the below command, it will 
    #  allow the process to use up much more of the CPU. Currently get 'cpu feature not supported' error.
    podman --storage-driver=vfs run  --privileged --platform linux/arm64 --entrypoint "/scripts/armentry.sh" -e BUILD_ARCH=$BUILD_ARCH -v /signing-keys:/signing-keys -v /mnt/image/recipe/:/mnt/image/recipe -v /mnt/image:/mnt/image -v /etc/cray/signing-keys/:/etc/cray/signing-keys -v /etc/cray/ca/:/etc/cray/ca/ -v /mnt/ca-rpm/:/mnt/ca-rpm docker://registry.local/$IMS_ARM_BUILDER
}

function run_remote_build() {
    echo "Running remote build on host: $REMOTE_BUILD_NODE"

    # set the arch on this job
    PODMAN_ARCH="linux/amd64"
    if [ "$BUILD_ARCH" == "aarch64" ]; then
        PODMAN_ARCH="linux/arm64"
    fi

    # Set up the ssh keys for access to the remote node
    mkdir -p ~/.ssh
    cp /etc/cray/remote-keys/id_ecdsa ~/.ssh
    chmod 600 ~/.ssh/id_ecdsa
    ssh-keygen -y -f ~/.ssh/id_ecdsa > ~/.ssh/id_ecdsa.pub

    # NOTE - presence of the dir in /tmp on the remote node is used to signal a running job
    #   make sure this gets cleaned up on exit
    SSH_ARGS="-o StrictHostKeyChecking=no -o ServerAliveInterval=${SSH_SERVER_ALIVE_INTERVAL_SECONDS} -o ServerAliveCountMax=${SSH_SERVER_ALIVE_COUNT} -o ConnectTimeout=${SSH_CONNECTION_TIMEOUT_SECONDS} root@${REMOTE_BUILD_NODE}"
    ssh ${SSH_ARGS} "mkdir -p /tmp/ims_${IMS_JOB_ID}/image/"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create directory /tmp/ims_${IMS_JOB_ID} on remote node $REMOTE_BUILD_NODE."
        touch "$PARAMETER_FILE_BUILD_FAILED"
        exit 0
    fi
    # Modify the dockerfile to use the correct base image
    (echo "cat <<EOF" ; cat Dockerfile.remote ; echo EOF ) | sh > Dockerfile

    # The dockerfile expects a dir at `/etc/cray/signing-keys` which should be a mounted secret
    # If the dir does not exist, create it
    if [ ! -d /etc/cray/signing-keys ]; then
        echo "Creating /etc/cray/signing-keys directory"
        mkdir -p /etc/cray/signing-keys
    fi

    # build the docker image
    podman build --platform ${PODMAN_ARCH} -t ims-remote-${IMS_JOB_ID}:1.0.0 .

    # Copy docker image to remote node
    podman save ims-remote-${IMS_JOB_ID}:1.0.0 | ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_CONNECTION_TIMEOUT_SECONDS root@${REMOTE_BUILD_NODE} podman load
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to copy docker image to remote node $REMOTE_BUILD_NODE."
        touch "$PARAMETER_FILE_BUILD_FAILED"
        exit 0
    fi

    # remote run of the docker image
    ## NOTE: do not use '-rm' tag as we want access to the results
    ssh ${SSH_ARGS} "podman run --name ims-${IMS_JOB_ID} --privileged -t -i -v /tmp/ims_${IMS_JOB_ID}/image:/mnt/image ims-remote-${IMS_JOB_ID}:1.0.0"
    brc=$?
    if [[ $brc -eq 255 ]]; then
        echo "ERROR: ssh connection failed to remote host."
    elif [[ $brc -ne 0 ]]; then
        echo "ERROR: Kiwi build failed on remote host with return code: $brc"
    fi

    # check the results of the build
    ssh ${SSH_ARGS} "podman cp ims-${IMS_JOB_ID}:${IMAGE_ROOT_PARENT}/build_succeeded /tmp/ims_${IMS_JOB_ID}/"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        # If the build failed, we will not have a build_succeeded file
        # Failed rc indicates file not present
        echo "ERROR: Kiwi build failed on remote host."
        touch "$PARAMETER_FILE_BUILD_FAILED"
    else
        # copy image files from remote machine to job pod - be picky so we don't copy large files we don't need
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/transfer.sqsh" "${IMAGE_ROOT_PARENT}"
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/kiwi.*" "${IMAGE_ROOT_PARENT}"
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/${KERNEL_FILENAME}" "${IMAGE_ROOT_PARENT}"
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/${INITRD_FILENAME}" "${IMAGE_ROOT_PARENT}"
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/${KERNEL_PARAMETERS_FILENAME}" "${IMAGE_ROOT_PARENT}"
        scp -o StrictHostKeyChecking=no "root@${REMOTE_BUILD_NODE}:/tmp/ims_${IMS_JOB_ID}/image/build_succeeded" "${IMAGE_ROOT_PARENT}"

    fi

    # delete artifacts off of remote host
    # NOTE: need to prune the anonymous volume explicitly to free up the space
    # rc=255 Connection failed, authentication failure, host unreachable, or timeout. In that case we should not perform any remote cleanup as ssh connection is not possible
    if [[ $rc -ne 255 ]]; then
      ssh ${SSH_ARGS} "rm -rf /tmp/ims_${IMS_JOB_ID}/"
      ssh ${SSH_ARGS} "podman rm ims-${IMS_JOB_ID}"
      ssh ${SSH_ARGS} "podman rmi ims-remote-${IMS_JOB_ID}:1.0.0"
      ssh ${SSH_ARGS} "podman volume prune -f"
      echo "Cleanup complete on remote host"
    fi
}

function run_local_build() {
    # Call kiwi to build the image recipe. Note that the command line --add-bootstrap-package
    # causes kiwi to install the cray-ca-cert rpm into the image root.
    echo "Calling kiwi-ng build..."

    # Copy all the DST signing keys into the signing-keys directory
    if [[ -d /etc/cray/signing-keys ]]; then
        for file in /etc/cray/signing-keys/*; do
            if [[ -f $file ]]; then
                cp "$file" /signing-keys/
            fi
        done
    fi

    # set up the signing keys args
    SIGNING_KEYS_ARGS=""
    for file in /signing-keys/*; do
        if [[ -f $file ]]; then
            new_len=$((${#SIGNING_KEYS_ARGS} + ${#file} + 14)) # 14 = length of "--signing-key "
            if [[ $new_len -lt 4096 ]]; then
                # If the length of the args is less than 4096, add the signing key
                # to the args list. If it is longer, skip it.
                # This is a workaround for the kiwi-ng command line length limit.
                SIGNING_KEYS_ARGS+="--signing-key $file "
            else
                echo "WARNING: Skipping signing key $file due to command line length limit."
            fi
        fi
    done

    kiwi-ng \
        $DEBUG_FLAGS \
        --logfile="$PARAMETER_FILE_KIWI_LOGFILE" \
        --type tbz system build \
        --description "$RECIPE_ROOT_PARENT" \
        --target "$IMAGE_ROOT_PARENT" \
        --add-bootstrap-package file:///mnt/ca-rpm/cray_ca_cert-1.0.1-1.noarch.rpm \
        $SIGNING_KEYS_ARGS
    RC=$?

    if [[ $RC -ne 0 ]]; then
        echo "ERROR: Kiwi reported a build error."
        touch "$PARAMETER_FILE_BUILD_FAILED"
    fi
}

# Make Cray's CA certificate a trusted system certificate within the container
# This will not install the CA certificate into the kiwi image root.
CA_CERT='/etc/cray/ca/certificate_authority.crt'
if [[ -e $CA_CERT ]]; then
	cp $CA_CERT  /usr/share/pki/trust/anchors/.
else
	echo "The CA certificate file: $CA_CERT is missing"
	exit 1
fi
update-ca-certificates
RC=$?
if [[ $RC -ne 0 ]]; then
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
