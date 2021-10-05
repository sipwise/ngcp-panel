package NGCP::Panel::Form::MailToFax::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';


has_field 'active' => (
    type => 'Boolean',
    label => 'Active',
    required => 0,
);

has_field 'secret_key' => (
    type => 'Text',
    label => 'Secret Key (empty=disabled)',
    required => 0,
);

has_field 'secret_key_renew' => (
    type => 'Select',
    options => [
        { label => 'Never', value => 'never' },
        { label => 'Daily', value => 'daily' },
        { label => 'Weekly', value => 'weekly' },
        { label => 'Monthly', value => 'monthly' },
    ],
    default => 'never',
    label => 'Secret Renew Interval ',
    required => 1,
);

has_field 'secret_renew_notify' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
);

has_field 'secret_renew_notify.destination' => (
    type => 'Text',
    label => 'Notify email',
    required => 1,
);

has_field 'acl' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'acl.from_email' => (
    type => 'Text',
    label => 'From email',
    required => 0,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.received_from' => (
    type => 'Text',
    label => 'Received from IP',
    required => 0,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 0,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.use_regex' => (
    type => 'Boolean',
    label => 'Use Regex',
    default => 0,
    required => 0,
    wrapper_class => [qw/hfh-rep-field/],
);

1;

# vim: set tabstop=4 expandtab:
