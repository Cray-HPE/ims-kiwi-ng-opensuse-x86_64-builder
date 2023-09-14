#!/bin/sh
#
# MIT License
#
# (C) Copyright 2023 Hewlett Packard Enterprise Development LP
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

RECIPE_ROOT_PARENT=${1:-/mnt/image/recipe}
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

# Call kiwi to build the image recipe. Note that the command line --add-bootstrap-package
# causes kiwi to install the cray-ca-cert rpm into the image root.
kiwi-ng \
    $DEBUG_FLAGS \
    --target-arch=$BUILD_ARCH \
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
  echo "Outputting kiwi log file."
  cat $PARAMETER_FILE_KIWI_LOGFILE
  touch $PARAMETER_FILE_BUILD_FAILED
fi

# Always return 0
exit 0
