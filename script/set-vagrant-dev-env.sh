#!/bin/sh

VAGRANT_MNT=/usr/local/devel

for i in Panel Panel.pm; do
  mv /usr/share/perl5/NGCP/$i /usr/share/perl5/NGCP/${i}.orig
  ln -s $VAGRANT_MNT/ngcp-panel/lib/NGCP/$i /usr/share/perl5/NGCP/$i
done

for i in ngcp_panel_fastcgi.pl; do
  mv /usr/share/ngcp-panel/$i /usr/share/ngcp-panel/${i}.orig
  ln -s $VAGRANT_MNT/ngcp-panel/script/$i /usr/share/ngcp-panel/$i
done

for i in script ngcp_panel.psgi; do
  mv /usr/share/ngcp-panel/$i /usr/share/ngcp-panel/${i}.orig
  ln -s $VAGRANT_MNT/ngcp-panel/$i /usr/share/ngcp-panel/$i
done

for i in layout static templates tools; do
  mv /usr/share/ngcp-panel/$i /usr/share/ngcp-panel/${i}.orig
  ln -s $VAGRANT_MNT/ngcp-panel/share/$i /usr/share/ngcp-panel/$i
done


for i in Schema Schema.pm InterceptSchema.pm; do
  mv /usr/share/perl5/NGCP/$i /usr/share/perl5/NGCP/${i}.orig
  ln -s $VAGRANT_MNT/ngcp-schema/lib/NGCP/$i /usr/share/perl5/NGCP/$i
done
