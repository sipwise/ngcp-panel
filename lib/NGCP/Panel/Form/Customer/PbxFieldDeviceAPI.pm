package NGCP::Panel::Form::Customer::PbxFieldDeviceAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has_field 'profile_id' => (
);
has_field 'profile' => (
    type => 'Compound',
);
has_field 'profile.id' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Device Profile',
);
has_field 'contract' => (
    type => 'Compound',
);
has_field 'contract.id' => (
    type => 'Text',
);

has_field 'identifier' => (
    type => 'Text',
    required => 1,
    label => 'MAC Address / Identifier',
);

has_field 'station_name' => (
    type => 'Text',
    required => 1,
    label => 'Station Name',
);

has_field 'lines' => (
    type => 'Repeatable',
    label => 'Lines/Keys',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
);

has_field 'lines.id' => (
    type => 'Hidden',
);

has_field 'lines.subscriber_id' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Subscriber',
    options_method => \&build_subscribers,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber to use on this line/key'],
    },
);

has_field 'lines.line' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key',
    element_attr => {
        rel => ['tooltip'],
        title => ['The line/key to use'],
    },
);
sub validate_line_line {
    my ($self, $field) = @_;
    $field->clear_errors;
    unless($field->value =~ /^\d+\.\d+\.\d+$/) {
        my $err_msg = 'Invalid line value';
        $field->add_error($err_msg);
    }
    return;
}

has_field 'lines.type' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key Type',
    options => [],
    no_option_validation => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The type of feature to use on this line/key'],
    },
    element_class => [qw/ngcp-linetype-select/],
);
sub validate_line_type {
    my ($self, $field) = @_;
    $field->clear_errors;
    unless($field->value eq 'private' ||
           $field->value eq 'shared' ||
           $field->value eq 'blf') {
        my $err_msg = 'Invalid line type, must be private, shared or blf';
        $field->add_error($err_msg);
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
