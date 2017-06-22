package NGCP::Panel::Form::CallListSuppression::Suppression;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden'
);

has_field 'domain' => (
    type => 'Text',
    label => 'The domain of subscribers, this call list suppression applies to. An empty domain means to apply it to subscribers of any domain.',
    required => 0,
);

has_field 'direction' => (
    type => 'Select',
    label => 'The direction of calls this call list suppression applies to.',
    options => [
        { value => 'outgoing', label => 'outgoing' },
        { value => 'incoming', label => 'incoming' },
    ],
    required => 1,
);

has_field 'pattern' => (
    type => 'Text',
    label => 'A regular expression the dialed number (CDR \'destination user in\') has to match in case of \'outgoing\' direction, or the inbound number (CDR \'source cli\') in case of \'incoming\' direction.',
    required => 1,
);

has_field 'mode' => (
    type => 'Select',
    label => 'The suppression mode. For subscriber and subscriber admins, filtering means matching calls do not appear at all, while obfuscation means the number is replaced by the given label.',
    options => [
        { value => 'filter', label => 'filter' },
        { value => 'obfuscate', label => 'obfuscate' },
        { value => 'disabled', label => 'disabled' },
    ],
    required => 1,
);

has_field 'label' => (
    type => 'Text',
    label => 'The replacement string in case of obfuscation mode. Admin and reseller users see it for filter mode suppressions.',
    required => 1,
);

1;
