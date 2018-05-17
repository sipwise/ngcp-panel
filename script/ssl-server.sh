#!/bin/sh

export CATALYST_DEBUG=1
export DBIC_TRACE=1
export DBIC_TRACE_PROFILE=console
export DEVEL_CONFESS_OPTIONS='objects builtin dump color source'

perl "$(which plackup)" \
  -I ../data-hal/lib \
  -I ../ngcp-schema/lib \
  -I lib \
  -I ../sipwise-base/lib/ \
  ngcp_panel.psgi --listen /tmp/ngcp_panel_sock --nproc 1 -s FCGI -r
