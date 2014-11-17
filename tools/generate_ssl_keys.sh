#!/bin/sh

set -e
set -u

# configurable
DEST="${1:-}"
BASE="${2:-/usr/share/ngcp-panel-tools}"
FILE="${3:-api_ca}"

if [ -z "${1:-}" ] ; then
  echo "Usage: $0 <destination_directory> [<basedir> <filename]>" >&2
  echo
  echo "If unset <basedir> defaults to $BASE and <filename> defaults to $FILE"
  echo
  echo "Usage example:

  $0 /etc/ngcp-config/ssl /usr/share/ngcp-panel-tools myserver
"
  exit 1
fi

# static configuration
OPENSSL_CONFIG="${BASE}/opensslcnf.cnf"
KEY_FILE="${DEST}/${FILE}.key"
CSR_FILE="${DEST}/${FILE}.csr"
CRT_FILE="${DEST}/${FILE}.crt"

mkdir -p "${DEST}"

# avoid leakage during execution
umask 077

echo "Generating OpenSSL certificate files in directory ${DEST}:"
/usr/bin/openssl genrsa -out "${KEY_FILE}" 4096 -config "${OPENSSL_CONFIG}" -batch
/usr/bin/openssl req -new -out "${CSR_FILE}" -key "${KEY_FILE}" -config "${OPENSSL_CONFIG}" -batch
/usr/bin/openssl x509 -req -in "${CSR_FILE}" -signkey "${KEY_FILE}" -out "${CRT_FILE}" -extfile "${OPENSSL_CONFIG}"

chmod 640 "${KEY_FILE}" "${CRT_FILE}"
chmod 600 "${CSR_FILE}"

echo "Generated ${KEY_FILE} ${CRT_FILE} ${CSR_FILE}"

echo "Finished execution of $0"
