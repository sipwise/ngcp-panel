#!/bin/sh
DEST=${1:-/etc/ngcp-panel/api_ssl}
BASE=${2:-/usr/share/ngcp-panel-tools}
FILE=${3:-api_ca}

mkdir -p ${DEST}

/usr/bin/openssl req -x509 -config ${BASE}/opensslcnf.cnf \
	-newkey rsa:4096 -keyout ${DEST}/${FILE}.key -out ${DEST}/${FILE}.crt \
	-days 999 -nodes -batch
