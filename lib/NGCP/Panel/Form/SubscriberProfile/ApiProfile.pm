package NGCP::Panel::Form::SubscriberProfile::ApiProfile;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::SubscriberProfile::ProfileReseller';
use Moose::Util::TypeConstraints;

has_field 'profile_set' => (
    type => '+NGCP::Panel::Field::SubscriberProfileSet',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile set defining the possible feature sets for this subscriber.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/profile_set name description profile_default/],
);

1;

# vim: set tabstop=4 expandtab:
