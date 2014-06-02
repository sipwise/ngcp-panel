#!/bin/bash -e

I18_DIRS="lib/NGCP/Panel/Role \
lib/NGCP/Panel/Field \
lib/NGCP/Panel/AuthenticationStore \
lib/NGCP/Panel/Form \
lib/NGCP/Panel/Render \
lib/NGCP/Panel/Controller \
lib/NGCP/Panel/Model \
lib/NGCP/Panel/Utils \
lib/NGCP/Panel/Widget \
lib/NGCP/Panel/View \
lib/NGCP/Panel/Cache \
share/templates \
share/layout"

POT="lib/NGCP/Panel/I18N/messages.pot"

DIRS=""
for d in ${I18_DIRS}; do
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
	msgmerge --no-fuzzy-matching --update $po $POT
done
