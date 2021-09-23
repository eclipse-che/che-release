#!/bin/bash -e
#
# Copyright (c) 2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#

# update secrets from provided secrets file into the specified list of repos (see updateSecrets.txt for repo list)


usage ()
{
echo "
For a given list of Github repos, push secret name/value pairs in a secrets file to those repos.
Existing secrets will be overwritten.

Repos file should include one org/repo per line. For example:

eclipse-che/che-server
eclipse-che/che-theia
...

Secrets file should include one secret name and value, space-separated, per line. For example:
QUAY_USERNAME my-quay-username
QUAY_PASSWORD my-quay-password
...

Usage:   $0 -r [LIST OF REPOS FILE] -s [SECRETS FILE]
Example: $0 -r updateSecrets.txt -s /path/to/all-my-secrets.txt

Options: 
	-v               verbose output
	--dry-run        display planned changes but do not actually push new/updated secrets
	--help, -h       help
"
exit
}

if [[ $# -lt 1 ]]; then usage; exit; fi

#defaults
WORKDIR=$(pwd)
UPDATE_SECRETS=1
REPOSFILE="updateSecrets.txt"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-w') WORKDIR="$2"; shift 1;;
    '-r') REPOSFILE="$2"; shift 1;;
    '-s') SECRETSFILE="$2"; shift 1;;
    '-v') VERBOSE=1; shift 0;;
	'--dry-run') UPDATE_SECRETS=0; shift 0;;
    '--help'|'-h') usage;;
    *) OTHER="${OTHER} $1"; shift 0;; 
  esac
  shift 1
done

# check for valid files
if [[ ! "$SECRETSFILE" ]]; then echo "Error: Secrets file not set."; usage; fi
if [[ ! -r "$SECRETSFILE" ]] && [[ ! -r "${WORKDIR}/${SECRETSFILE}" ]]; then 
    echo "Error: Invalid repos file ${SECRETSFILE}."; usage
else
    if [[ -r "${WORKDIR}/$SECRETSFILE" ]]; then
        SECRETSFILE="${WORKDIR}/$SECRETSFILE"
    fi
fi

if [[ ! "$REPOSFILE" ]]; then echo "Error: Repos file not set."; usage; fi
if [[ ! -r "$REPOSFILE" ]] && [[ ! -r "${WORKDIR}/${REPOSFILE}" ]]; then 
    echo "Error: Invalid repos file ${REPOSFILE}."; usage
else
    if [[ -r "$REPOSFILE" ]]; then
        REPOS=$(cat "$REPOSFILE")
    elif [[ -r "${WORKDIR}/$REPOSFILE" ]]; then
        REPOS=$(cat "${WORKDIR}/$REPOSFILE")
    fi
fi

PODMAN=$(command -v podman)
if [[ ! -x $PODMAN ]]; then
  echo "[WARNING] podman is not installed."
 PODMAN=$(command -v docker)
  if [[ ! -x $PODMAN ]]; then
    echo "[ERROR] docker is not installed. Aborting."; exit 1
  fi
fi

# get the secret uploader tool and build it
# requires podman or docker to build the generator image
if [[ ! -d /tmp/github-secrets-generator ]]; then
    cd /tmp; git clone git@github.com:nickboldt/github-secrets-generator.git
else
    if [[ ! $($PODMAN images github-secrets-generator | grep github-secrets-generator) ]]; then 
        cd /tmp/github-secrets-generator && ./run.sh --build
    fi
fi

cd /tmp/github-secrets-generator
for repo in $REPOS; do
    if [[ ${UPDATE_SECRETS} -eq 1 ]]; then
        ./run.sh -r ${repo} --list # -f "${SECRETSFILE}"
    else
        echo "run.sh -r ${repo} -f ${SECRETSFILE}"
    fi
done

