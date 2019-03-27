#!/bin/sh

VAGRANT_MNT=${VAGRANT_MNT:-/usr/local/devel}

for i in Panel Panel.pm Schema Schema.pm InterceptSchema.pm; do
  if [ -L "/usr/share/perl5/NGCP/$i" ] && [ -e "/usr/share/perl5/NGCP/${i}.orig" ]; then
    rm "/usr/share/perl5/NGCP/$i"
    mv "/usr/share/perl5/NGCP/${i}.orig" "/usr/share/perl5/NGCP/$i"
  fi
done

for i in ngcp_panel_fastcgi.pl ngcp_panel.psgi layout static templates tools script; do
  if [ -L "/usr/share/ngcp-panel/$i" ] && [ -e "/usr/share/ngcp-panel/${i}.orig" ]; then
    rm "/usr/share/ngcp-panel/$i"
    mv "/usr/share/ngcp-panel/${i}.orig" "/usr/share/ngcp-panel/$i"
  fi
done
