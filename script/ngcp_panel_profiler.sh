#!/bin/sh

export NYTPROF=sigexit=1:file=/tmp/nytprof.out
CATALYST_DEBUG=1 DBIC_TRACE=1 DBIC_TRACE_PROFILE=console DEVEL_CONFESS_OPTIONS='objects builtin dump color source' perl -I ../data-hal/lib -I ../ngcp-schema/lib -I lib -I ../sipwise-base/lib/ -d:NYTProf script/ngcp_panel_server.pl --port 1444
