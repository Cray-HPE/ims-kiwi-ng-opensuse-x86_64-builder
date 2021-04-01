#!/bin/sh
# Copyright 2019,2021 Hewlett Packard Enterprise Development LP
set -x

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

python3 -m ims_python_helper image set_job_status $IMS_JOB_ID building_image

DEBUG_FLAGS=""
if [[ `echo $ENABLE_DEBUG | tr [:upper:] [:lower:]` = "true" ]]; then
    DEBUG_FLAGS="--debug"
fi

# Call kiwi to build the image recipe. Note that the command line --add-bootstrap-package
# causes kiwi to install the cray-ca-cert rpm into the image root.
kiwi-ng $DEBUG_FLAGS --logfile=$PARAMETER_FILE_KIWI_LOGFILE --type tbz system build --description $RECIPE_ROOT_PARENT --target $IMAGE_ROOT_PARENT --add-bootstrap-package file:///mnt/ca-rpm/cray_ca_cert-1.0.1-1.x86_64.rpm
rc=$?

if [ "$rc" -ne "0" ]; then
  echo "ERROR: Kiwi reported a build error."
  touch $PARAMETER_FILE_BUILD_FAILED
fi

# Always return 0
exit 0
