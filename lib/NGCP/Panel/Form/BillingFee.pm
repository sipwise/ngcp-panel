package NGCP::Panel::Form::BillingFee;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'source' => (
    type => '+NGCP::Panel::Field::Regexp',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['A POSIX regular expression to match the calling number (e.g. ^.+$).']
    },
);

has_field 'destination' => (
    type => '+NGCP::Panel::Field::Regexp',
    maxlength => 255,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A POSIX regular expression to match the called number (e.g. ^431.+$).']
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { value => 'in', label => 'inbound' },
        { value => 'out', label => 'outbound' },
    ],
    default => 'out',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The call direction when to apply this fee (either for inbound or outbound calls).']
    },
);

has_field 'billing_zone' => (
    type => '+NGCP::Panel::Field::BillingZone',
    label => 'Zone',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing zone id this fee belongs to.']
    },
);

has_field 'onpeak_init_rate' => (
    type => 'Float',
    precision => 18,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost of the first interval in cents per second (e.g. 0.90).']
    },
    default => 0,
);

has_field 'onpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of the first interval in seconds (e.g. 60).']
    },
    default => 60,
    required => 1,
    validate_method => \&validate_interval,
);

has_field 'onpeak_follow_rate' => (
    type => 'Float',
    precision => 18,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost of each following interval in cents per second (e.g. 0.90).']
    },
    default => 0,
);

has_field 'onpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each following interval in seconds (e.g. 30).']
    },
    default => 60,
    required => 1,
    validate_method => \&validate_interval,
);

has_field 'offpeak_init_rate' => (
    type => 'Float',
    precision => 18,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost of the first interval in cents per second (e.g. 0.90).']
    },
    default => 0,
);

has_field 'offpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of the first interval in seconds (e.g. 60).']
    },
    default => 60,
    required => 1,
    validate_method => \&validate_interval,
);

has_field 'offpeak_follow_rate' => (
    type => 'Float',
    precision => 18,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost of each following interval in cents per second (e.g. 0.90).']
    },
    default => 0,
);

has_field 'offpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each following interval in seconds (e.g. 30).']
    },
    default => 60,
    required => 1,
    validate_method => \&validate_interval,
);

has_field 'use_free_time' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether free minutes may be used when calling this destination.']
    },
    default => 0,
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/billing_zone source destination direction
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval use_free_time
        /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_interval {
    my ($self, $field) = @_;

    if(int($field->value) < 1) {
        $field->add_error("Invalid interval, must be bigger than 0");
    }
}

1;
# vim: set tabstop=4 expandtab:
