#!/bin/sh

export PERL5LIB=/opt/Komodo-IDE-9/remote_debugging
export PERLDB_OPTS="RemotePort=127.0.0.1:9000"
export DBGP_IDEKEY="jdoe"
export CATALYST_DEBUG=1
export DBIC_TRACE=1
export DBIC_TRACE_PROFILE=console
export DEVEL_CONFESS_OPTIONS='objects builtin dump color source'

perl -d `which plackup` \
  -I ../data-hal/lib \
  -I ../ngcp-schema/lib \
  -I lib \
  -I ../sipwise-base/lib/ \
  ngcp_panel.psgi --listen /tmp/ngcp_panel_sock --nproc 2 -s FCGI -r
