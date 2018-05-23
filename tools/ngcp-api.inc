#!/bin/bash

set -e

importcreds () {
  local CREDS=$1

  if [ -z "${CREDS}" ]; then
    echo "Error: missing mandatory file name to read" >&2
    exit 1
  fi

  if [ ! -f "${CREDS}" ]; then
    return
  fi

  if [ ! -r "${CREDS}" ]; then
    echo "Error: cannot read ${CREDS}" >&2
    exit 1
  fi

  echo "${CREDS} present, checking perms"
  if stat "${CREDS}" | grep -q 'Access: (0600' 1>/dev/null ; then
    echo "${CREDS} permissions ok"
    . "${CREDS}"
  else
    echo "Error: ${CREDS} must have permissions 600" >&2
    exit 1
  fi
}
