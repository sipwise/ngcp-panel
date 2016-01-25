#!/bin/sh

VAGRANT_MNT=${VAGRANT_MNT:-/usr/local/devel}

for i in Panel Panel.pm; do
  if [ -L "/usr/share/perl5/NGCP/$i" ]; then
    echo "/usr/share/perl5/NGCP/$i is already a link, ignoring..."
  else
    mv "/usr/share/perl5/NGCP/$i" "/usr/share/perl5/NGCP/${i}.orig"
    ln -s "$VAGRANT_MNT/ngcp-panel/lib/NGCP/$i" "/usr/share/perl5/NGCP/$i"
  fi
done

#for i in ngcp_panel_fastcgi.pl; do
i=ngcp_panel_fastcgi.pl
  if [ -L "/usr/share/ngcp-panel/$i" ]; then
    echo "/usr/share/ngcp-panel/$i is already a link, ignoring..."
  else
    mv "/usr/share/ngcp-panel/$i" "/usr/share/ngcp-panel/${i}.orig"
    ln -s "$VAGRANT_MNT/ngcp-panel/script/$i" "/usr/share/ngcp-panel/$i"
  fi
#done

#for i in script ngcp_panel.psgi; do
i=script ngcp_panel.psgi
  if [ -L "/usr/share/ngcp-panel/$i" ]; then
    echo "/usr/share/ngcp-panel/$i is already a link, ignoring..."
  else
    mv "/usr/share/ngcp-panel/$i" "/usr/share/ngcp-panel/${i}.orig"
    ln -s "$VAGRANT_MNT/ngcp-panel/$i" "/usr/share/ngcp-panel/$i"
  fi
#done

for i in layout static templates tools; do
  if [ -L "/usr/share/ngcp-panel/$i" ]; then
    echo "/usr/share/ngcp-panel/$i is already a link, ignoring..."
  else
    mv "/usr/share/ngcp-panel/$i" "/usr/share/ngcp-panel/${i}.orig"
    ln -s "$VAGRANT_MNT/ngcp-panel/share/$i" "/usr/share/ngcp-panel/$i"
  fi
done


for i in Schema Schema.pm InterceptSchema.pm; do
  if [ -L "/usr/share/ngcp-panel/$i" ]; then
    echo "/usr/share/perl5/NGCP/$i is already a link, ignoring..."
  else
    mv "/usr/share/perl5/NGCP/$i" "/usr/share/perl5/NGCP/${i}.orig"
    ln -s "$VAGRANT_MNT/ngcp-schema/lib/NGCP/$i" "/usr/share/perl5/NGCP/$i"
  fi
done
