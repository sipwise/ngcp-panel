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
        title => ['Source set mode. If set to "blacklist" it enables forwarding for everything except numbers in the list, and "whitelist" only enables forwards for numbers defined in this list. This field is mandatory.']
    },
);

has_field 'is_regex' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['A flag indicating, whether the numbers in this set are regular expressions. ' .
            'If true, all sources will be interpreted as perl compatible regular expressions and ' .
            'matched against the calling party number (in E164 format) of the calls. If false, the whole numbers ' .
            'are plainly matched while shell patterns like 431* or 49123~[1-5~]67 are possible.'],
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
                  'Regular expressions or shell patterns can be used depending on the is_regex flag. ' .
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
