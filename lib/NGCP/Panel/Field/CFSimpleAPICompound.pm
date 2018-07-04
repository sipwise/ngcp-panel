package NGCP::Panel::Field::CFSimpleAPICompound;
 
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'destinations.destination' => (
    type => 'Text',
);

has_field 'destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'sources.source' => (
    type => 'Text',
);

has_field 'sources_mode' => (
    type => 'Select',
    options => [
        { value => 'whitelist', label => 'Whitelist' },
        { value => 'blacklist', label => 'Blacklist' },
    ],
    default => 'whitelist',
);

has_field 'sources_is_regex' => (
    type => 'Boolean',
    default => 0,
);

has_field 'bnumbers' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'bnumbers.bnumber' => (
    type => 'Text',
);

has_field 'bnumbers_mode' => (
    type => 'Select',
    options => [
        { value => 'whitelist', label => 'Whitelist' },
        { value => 'blacklist', label => 'Blacklist' },
    ],
    default => 'whitelist',
);

has_field 'bnumbers_is_regex' => (
    type => 'Boolean',
    default => 0,
);

no Moose;
1;

# vim: set tabstop=4 expandtab: