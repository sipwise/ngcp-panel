package NGCP::Panel::Form::BillingFee;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;
use NGCP::Panel::Utils::Billing qw();

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'match_mode' => (
    type => 'Select',
    options => [
        { value => 'regex_longest_pattern', label => 'Regular expression - longest pattern' },
        { value => 'regex_longest_match', label => 'Regular expression - longest match' },
        { value => 'prefix', label => 'Prefix string' },
        { value => 'exact_destination', label => 'Exact string (destination)' },
    ],
    default => 'regex_longest_pattern',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The mode how the fee\'s source/destination has to match a call\'s source/destination.']
    },
);

has_field 'source' => (
    type => 'Text',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['A string (eg. 431001), string prefix (eg. 43) or PCRE regular expression (eg. ^.+$) to match the calling number or sip uri.']
    },
);

has_field 'destination' => (
    type => 'Text',
    maxlength => 255,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A string (eg. 431001), string prefix (eg. 43) or PCRE regular expression (eg. ^.+$) to match the called number or sip uri.']
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
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of the first interval during onpeak hours (e.g. 0.90 cent).']
    },
    default => 0,
);

has_field 'onpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of the first interval during onpeak hours in seconds (e.g. 60).']
    },
    default => 60,
    required => 1,
);

has_field 'onpeak_follow_rate' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of each following interval during onpeak hours in cents (e.g. 0.90 cents).']
    },
    default => 0,
);

has_field 'onpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each following interval during onpeak hours in seconds (e.g. 30).']
    },
    default => 60,
    required => 1,
);

has_field 'offpeak_init_rate' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of the first interval during offpeak hours in cents (e.g. 0.70 cents).']
    },
    default => 0,
);

has_field 'offpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of the first interval during offpeak hours in seconds (e.g. 60).']
    },
    default => 60,
    required => 1,
);

has_field 'offpeak_follow_rate' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of each following interval during offpeak hours in cents (e.g. 0.70 cents).']
    },
    default => 0,
);

has_field 'offpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each following interval during offpeak hours in seconds (e.g. 30).']
    },
    default => 60,
    required => 1,
);

has_field 'onpeak_use_free_time' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Free calling time may be used when calling this destination during on-peak hours.']
    },
    default => 0,
);

has_field 'offpeak_use_free_time' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Free calling time may be used when calling this destination during off-peak hours.']
    },
    default => 0,
);

has_field 'onpeak_extra_rate' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of each extra interval during onpeak hours in cents (e.g. 0.70 cents).']
    },
    default => 0,
);

has_field 'onpeak_extra_second' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each extra interval during onpeak hours in seconds (e.g. 30).']
    },
    default => undef,
    required => 0,
);

has_field 'offpeak_extra_rate' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost per second of each extra interval during offpeak hours in cents (e.g. 0.70 cents).']
    },
    default => 0,
);

has_field 'offpeak_extra_second' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of each extra interval during offpeak hours in seconds (e.g. 30).']
    },
    default => undef,
    required => 0,
);

has_field 'aoc_pulse_amount_per_message' => (
    type => 'Float',
    size => 15,
    precision => 14,
    element_attr => {
        rel => ['tooltip'],
        title => ['The rate of a single AoC pulse message (e.g. 1 cent). For values greater than 0 cents (and follow rate greater than 0 cents), the resulting AoC pulse frequency is given by (<AoC pulse message rate> * <follow interval> / <follow rate>) seconds. This allows you to configure intervals for AoC pulse messages of less than 1 second.']
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
    render_list => [qw/billing_zone match_mode source destination direction
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval onpeak_use_free_time offpeak_use_free_time
        onpeak_extra_rate onpeak_extra_second offpeak_extra_rate offpeak_extra_second aoc_pulse_amount_per_message
        /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {

    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    NGCP::Panel::Utils::Billing::validate_billing_fee(
        $self->values,
        sub {
            my ($field,$error,$error_detail) = @_;
            $self->field($field)->add_error($self->field($field)->label . ' ' . $error);
            return 1;
        },
        sub {
            my ($field) = @_;
            return $self->field($field)->value;
        },
    )

}

1;
# vim: set tabstop=4 expandtab:
