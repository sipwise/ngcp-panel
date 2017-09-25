package NGCP::Panel::Form::CallForward::CFSourceSetSubAPI;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the source set']
    },
);

has_field 'mode' => (
    type => 'Select',
    options => [
        {value => 'whitelist', label => 'whitelist'},
        {value => 'blacklist', label => 'blacklist'},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The source set mode. A blacklist forwards everything except numbers in the list, a whitelist only forwards numbers in this list.']
    },
);

has_field 'sources' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of sources, each containing the key "source" ' .
                  'which will be matched against the calling party number to determine ' .
                  'whether to apply the callforward or not. ' .
                  '"source" is the calling party number in E164 format to match. ' .
                  'Shell patterns like 431* or 49123[1-5]67 are possible. ' .
                  'Use "anonymous" to match suppressed numbers.',
        ],
    },
);

has_field 'sources.id' => (
    type => 'Hidden',
);

has_field 'sources.source' => (
    type => 'Text',
    label => 'Source',
);

1;

# vim: set tabstop=4 expandtab:
