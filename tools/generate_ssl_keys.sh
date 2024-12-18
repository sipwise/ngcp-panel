#!/bin/sh

set -e
set -u

# configurable
DEST="${1:-}"
BASE="${2:-/usr/share/ngcp-panel-tools}"
FILE="${3:-api_ca}"
SKIP_CSR="${SKIP_CSR:-}"

if [ -z "${1:-}" ] ; then
  echo "Usage: $0 <destination_directory> [<basedir> <filename]>" >&2
  echo
  echo "If unset <basedir> defaults to $BASE and <filename> defaults to $FILE"
  echo
  echo "Usage example:

  $0 /etc/ngcp-config/shared-files/ssl /usr/share/ngcp-panel-tools myserver
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

DAYS="$(sed -ne 's/^default_days[[:space:]]*=[[:space:]]*\([0-9]\+\).*$/\1/p;Tn;q;:n' \
  "${OPENSSL_CONFIG}")"

if [ "$SKIP_CSR" = "true" ] ; then
  echo "Skipping generation of csr file as requested via SKIP_CSR environment variable."
  echo "Generating only key and crt files now."
  /usr/bin/openssl req -x509 -days "${DAYS}" \
       -config "${OPENSSL_CONFIG}" \
       -newkey rsa:4096            \
       -keyout "${KEY_FILE}"       \
       -out "${CRT_FILE}"          \
       -nodes -batch
else
  OPENSSL_CONF="${OPENSSL_CONFIG}" /usr/bin/openssl genrsa \
    -out "${KEY_FILE}" 4096
  /usr/bin/openssl req -new -out "${CSR_FILE}" \
    -key "${KEY_FILE}" -config "${OPENSSL_CONFIG}" -batch
  /usr/bin/openssl x509 -days "${DAYS}" -req -in "${CSR_FILE}" \
    -signkey "${KEY_FILE}" -out "${CRT_FILE}" -extfile "${OPENSSL_CONFIG}"
fi

chmod 640 "${KEY_FILE}"
chmod 644 "${CRT_FILE}"
chown root:ssl-cert "${KEY_FILE}" "${CRT_FILE}"
if [ -r "${CSR_FILE}" ] ; then
  chmod 640 "${CSR_FILE}"
  chown root:ssl-cert "${CSR_FILE}"
fi

if [ "$SKIP_CSR" = "true" ] ; then
  echo "Generated ${KEY_FILE} ${CRT_FILE}"
else
  echo "Generated ${KEY_FILE} ${CRT_FILE} ${CSR_FILE}"
fi

echo "Finished execution of $0"
