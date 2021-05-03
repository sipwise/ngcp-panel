#!/bin/bash

set -e

declare -a I18_DIRS=()
I18_DIRS+=("lib/NGCP/Panel/Role")
I18_DIRS+=("lib/NGCP/Panel/Field")
I18_DIRS+=("lib/NGCP/Panel/AuthenticationStore")
I18_DIRS+=("lib/NGCP/Panel/Form")
I18_DIRS+=("lib/NGCP/Panel/Render")
I18_DIRS+=("lib/NGCP/Panel/Controller")
I18_DIRS+=("lib/NGCP/Panel/Model")
I18_DIRS+=("lib/NGCP/Panel/Utils")
I18_DIRS+=("lib/NGCP/Panel/Widget")
I18_DIRS+=("lib/NGCP/Panel/View")
I18_DIRS+=("lib/NGCP/Panel/Cache")
I18_DIRS+=("share/templates")
I18_DIRS+=("share/layout")

POT="lib/NGCP/Panel/I18N/messages.pot"

echo; echo "Dumping DB and Form strings"; echo
perl -I../sipwise-base/lib -I../ngcp-schema/lib -Ilib script/ngcp_panel_dump_db_strings.pl

echo; echo "Creating ${POT}"; echo
xgettext.pl \
  --no-wrap \
  --output="${POT}" \
  "${I18_DIRS[@]/#/--directory=}" \
   -P perl=tt,pm

msgattrib \
  --no-wrap \
  --add-location=file \
  --width=100000 \
  --output-file="${POT}" \
  "${POT}"

while IFS= read -r -d '' po ; do
  echo; echo "Merging ${po}"; echo
  msgmerge \
    --no-fuzzy-matching \
    --no-wrap \
    --width=100000 \
    --add-location=file \
    --update \
    "${po}" \
    "${POT}"
done < <(find lib/NGCP/Panel/I18N -name "*.po" -print0)

echo; echo "Removing line numbers"; echo
sed -i -e '/#: /s!\(\(lib\|share\)\S*\):[0-9]*!\1!g' lib/NGCP/Panel/I18N/*
