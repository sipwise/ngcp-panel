#!/bin/bash -e

POT="lib/NGCP/Panel/I18N/messages.pot"

DIRS=""
for d in $(cat etc/i18n.inc); do 
	DIRS="$DIRS --directory $d"; 
done

echo; echo "Dumping DB and Form strings"; echo
perl -I../sipwise-base/lib -I../ngcp-schema/lib -Ilib script/ngcp_panel_dump_db_strings.pl

echo; echo "Creating $POT"; echo
xgettext.pl \
	--output=$POT \
	$DIRS \
	 -P perl=tt,pm

for po in $(find lib/NGCP/Panel/I18N -name "*.po"); do
	echo; echo "Merging $po"; echo
	msgmerge --update $po $POT
done
