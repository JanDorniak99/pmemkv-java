#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2017-2021, Intel Corporation

#
# build.sh - runs a Docker container from a Docker image with environment
#            prepared for running pmemkv-java build(s) and tests.
#
# Notes:
# - if running this script locally, following variables has to be set:
#   - 'HOST_WORKDIR' to where the root of this project is on the host machine,
#   - 'OS' and 'OS_VER' to a system and its version, you want to build this repo on
#     (for delivered OSes take a look at the list of Dockerfiles at the
#     utils/docker/images directory), eg. OS=ubuntu, OS_VER=20.04.
#   - 'PMEMKV' to a pmemkv's branch, e.g. 'master' or 'stable-1.0'
#

set -e

source $(dirname $0)/set-ci-vars.sh
IMG_VER=${IMG_VER:-devel}

if [[ "$CI_EVENT_TYPE" != "cron" && "$CI_BRANCH" != "coverity_scan" \
	&& "$TYPE" == "coverity" ]]; then
	echo "INFO: Skip Coverity scan job if build is triggered neither by " \
		"'cron' nor by a push to 'coverity_scan' branch"
	exit 0
fi

if [[ ( "$CI_EVENT_TYPE" == "cron" || "$CI_BRANCH" == "coverity_scan" )\
	&& "$TYPE" != "coverity" ]]; then
	echo "INFO: Skip regular jobs if build is triggered either by 'cron'" \
		" or by a push to 'coverity_scan' branch"
	exit 0
fi

if [[ -z "$OS" || -z "$OS_VER" ]]; then
	echo "ERROR: The variables OS and OS_VER have to be set " \
		"(eg. OS=fedora, OS_VER=31)."
	exit 1
fi

if [[ -z "$HOST_WORKDIR" ]]; then
	echo "ERROR: The variable HOST_WORKDIR has to contain a path to " \
		"the root of this project on the host machine"
	exit 1
fi

if [[ -z "${CONTAINER_REG}" ]]; then
	echo "ERROR: CONTAINER_REG environment variable is not set " \
		"(e.g. \"<registry_addr>/<org_name>/<package_name>\")."
	exit 1
fi

TAG="${OS}-${OS_VER}-${IMG_VER}"
IMAGE_NAME=${CONTAINER_REG}:${TAG}
containerName=pmemkv-java-${OS}-${OS_VER}

if [[ "$command" == "" ]]; then
	command="./run-build.sh $PMEMKV";
fi

if [ "$COVERAGE" == "1" ]; then
	docker_opts="${docker_opts} `bash <(curl -s https://codecov.io/env)`";
fi

if [ -n "$DNS_SERVER" ]; then DNS_SETTING=" --dns=$DNS_SERVER "; fi

# Only run doc update on $GITHUB_REPO master or stable branch
if [[ -z "${CI_BRANCH}" || -z "${TARGET_BRANCHES[${CI_BRANCH}]}" || "$CI_EVENT_TYPE" == "pull_request" || "$CI_REPO_SLUG" != "${GITHUB_REPO}" ]]; then
	AUTO_DOC_UPDATE=0
fi

# Check if we are running on a CI (Travis or GitHub Actions)
[ -n "$GITHUB_ACTIONS" -o -n "$TRAVIS" ] && CI_RUN="YES" || CI_RUN="NO"

# do not allocate a pseudo-TTY if we are running on GitHub Actions
[ ! $GITHUB_ACTIONS ] && TTY='-t' || TTY=''

WORKDIR=/pmemkv-java
SCRIPTSDIR=$WORKDIR/utils/docker

echo Building on ${OS}-${OS_VER}

# Run a container with
#  - environment variables set (--env)
#  - host directory containing source mounted (-v)
#  - working directory set (-w)
docker run --privileged=true --name=$containerName -i $TTY \
	${DNS_SETTING} \
	${docker_opts} \
	--env http_proxy=${http_proxy} \
	--env https_proxy=${https_proxy} \
	--env TERM=xterm-256color \
	--env WORKDIR=${WORKDIR} \
	--env SCRIPTSDIR=${SCRIPTSDIR} \
	--env GITHUB_REPO=${GITHUB_REPO} \
	--env CI_RUN=${CI_RUN} \
	--env TRAVIS=${TRAVIS} \
	--env GITHUB_ACTIONS=${GITHUB_ACTIONS} \
	--env CI_COMMIT=${CI_COMMIT} \
	--env CI_COMMIT_RANGE=${CI_COMMIT_RANGE} \
	--env CI_BRANCH=${CI_BRANCH} \
	--env CI_EVENT_TYPE=${CI_EVENT_TYPE} \
	--env CI_REPO_SLUG=${CI_REPO_SLUG} \
	--env DOC_UPDATE_GITHUB_TOKEN=${DOC_UPDATE_GITHUB_TOKEN} \
	--env DOC_UPDATE_BOT_NAME=${DOC_UPDATE_BOT_NAME} \
	--env DOC_REPO_OWNER=${DOC_REPO_OWNER} \
	--env COVERITY_SCAN_TOKEN=${COVERITY_SCAN_TOKEN} \
	--env COVERITY_SCAN_NOTIFICATION_EMAIL=${COVERITY_SCAN_NOTIFICATION_EMAIL} \
	--env COVERAGE=${COVERAGE} \
	--env AUTO_DOC_UPDATE=${AUTO_DOC_UPDATE} \
	--env TZ='Europe/Warsaw' \
	--shm-size=4G \
	-v ${HOST_WORKDIR}:${WORKDIR} \
	-v /etc/localtime:/etc/localtime \
	-w ${SCRIPTSDIR} \
	${IMAGE_NAME} ${command}
