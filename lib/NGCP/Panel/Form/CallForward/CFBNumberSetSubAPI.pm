package NGCP::Panel::Form::CallForward::CFBNumberSetSubAPI;
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
        title => ['The name of the bnumber set']
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
        title => ['The bnumber set mode. A blacklist matches everything except numbers in the list, a whitelist only matches numbers (or expressions) in this list.']
    },
);

has_field 'is_regex' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['A flag indicating, whether the numbers in this set are regular expressions. ' .
            'If true, all bnumbers will be interpreted as perl compatible regular expressions and ' .
            'matched against the B-Number of the calls. If false, shell pattern the whole numbers ' .
            'are matched while shell patterns like 431* or 49123~[1-5~]67 are possible. ' .
            'If true, capturing groups can be formed using parentheses and referenced in the ' .
            'destinations via \\1, \\2,... .'],
    },
);

has_field 'bnumbers' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of bnumbers, each containing the key "bnumber" ' .
                  'which will be matched against the called party number (callee) to determine ' .
                  'whether to apply the callforward or not. ' .
                  '"bnumber" is the callee\'s number in E164 format to match. ' .
                  'They are formatted either as regular expressions or shell patterns depending on the ' .
                  'value of the is_regex flag.',
        ],
    },
);

has_field 'bnumbers.id' => (
    type => 'Hidden',
);

has_field 'bnumbers.bnumber' => (
    type => 'Text',
    label => 'B-Number',
);

1;

# vim: set tabstop=4 expandtab:
