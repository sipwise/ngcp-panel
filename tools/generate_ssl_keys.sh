#!/bin/sh
DEST=${1:-/etc/ngcp-panel/api_ssl}
BASE=${2:-/usr/share/ngcp-panel-tools}

mkdir -p ${DEST}

/usr/bin/openssl req -x509 -config ${BASE}/opensslcnf.cnf \
	-newkey rsa:4096 -keyout ${DEST}/api_ca.key -out ${DEST}/api_ca.crt \
	-days 999 -nodes -batch
