#!/bin/bash

set -e

importcreds () {
  local CREDS=$1
  local PERMS=${2:-0600}

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
  if stat "${CREDS}" | grep -q "Access: (${PERMS}" 1>/dev/null ; then
    echo "${CREDS} permissions ok"
    # shellcheck source=./etc/default/ngcp-api
    . "${CREDS}"
  else
    echo "Error: ${CREDS} must have permissions ${PERMS}" >&2
    exit 1
  fi
}

validateurl() {
  local URL=$1

  # If we are using the legacy credentials, stop any validation.
  if [ -z "${APIREALM}" ]; then
    return
  fi

  local NGCP_API_HOST
  NGCP_API_HOST="$(getent hosts "${NGCP_API_IP}" | awk '{ print $2 }')"
  if ! [[ "${URL}" =~ ^https://${NGCP_API_IP}:${NGCP_API_PORT} ]] &&
     ! [[ "${URL}" =~ ^https://${NGCP_API_HOST}:${NGCP_API_PORT} ]]; then
    echo "Error: specified URL does not match expected URL for API credentials (https://${NGCP_API_IP}:${NGCP_API_PORT}/)" >&2
    exit 1
  fi
}
