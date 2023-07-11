#
# MIT License
#
# (C) Copyright 2019-2023 Hewlett Packard Enterprise Development LP
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
# If you wish to perform a local build, you will need to clone or copy the contents of the
# cms-meta-tools repo to ./cms_meta_tools

NAME ?= ims-kiwi-ng-opensuse-x86_64-builder
DOCKER_VERSION ?= $(shell head -1 .docker_version)
ifeq ($(IS_STABLE),true)
	DOCKER_NAME ?= artifactory.algol60.net/csm-docker/stable/$(NAME)
else
	DOCKER_NAME ?= artifactory.algol60.net/csm-docker/unstable/$(NAME)
endif

ifneq ($(wildcard ${HOME}/.netrc),)
        DOCKER_ARGS ?= --secret id=netrc,src=${HOME}/.netrc
endif

all : runbuildprep lint image 

runbuildprep:
		./cms_meta_tools/scripts/runBuildPrep.sh

lint:
		./cms_meta_tools/scripts/runLint.sh

image:
		docker buildx create --use
		docker buildx build --push --platform=linux/amd64,linux/arm64 ${DOCKER_ARGS} --tag '${DOCKER_NAME}:${DOCKER_VERSION}' .

image_local:
		docker buildx create --use
		docker buildx build --load ${DOCKER_ARGS} --tag '${DOCKER_NAME}:${DOCKER_VERSION}' .
