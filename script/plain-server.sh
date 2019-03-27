#!/bin/sh

export CATALYST_DEBUG=1
export DBIC_TRACE=1
export DBIC_TRACE_PROFILE=console
export DEVEL_CONFESS_OPTIONS='objects builtin dump color source'

perl \
  -I ../data-hal/lib \
  -I ../ngcp-schema/lib \
  -I lib \
  -I ../sipwise-base/lib/ \
  script/ngcp_panel_server.pl --port 1444 -r
