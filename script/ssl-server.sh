#!/bin/sh
CATALYST_DEBUG=1 DBIC_TRACE=1 DBIC_TRACE_PROFILE=console DEVEL_CONFESS_OPTIONS='objects builtin dump color source' perl `which plackup` -I ../ngcp-schema/lib -I lib -I ../sipwise-base/lib/ ngcp_panel.psgi --listen /tmp/ngcp_panel_sock --nproc 1 -s FCGI -r
