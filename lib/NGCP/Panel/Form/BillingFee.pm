package NGCP::Panel::Form::BillingFee;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;

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
        title => ['The mode how the the fee\'s source/destination has to match a call\'s source/destination.']
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
    render_list => [qw/billing_zone match_mode source destination direction
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

sub validate {

    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $match_mode = $self->values->{match_mode};
    if (defined $match_mode
        and ('regex_longest_pattern' eq $match_mode
        or 'regex_longest_match' eq $match_mode)) {
        foreach my $field (qw(source destination)) {
            my $pattern = $self->field($field)->value;
            if (defined $pattern and length($pattern) > 0) {
                eval {
                    qr/$pattern/;
                };
                if ($@) {
                    $self->field($field)->add_error($self->field($field)->label . " is no valid regexp");
                }
            }
        }
    }

    foreach my $field (qw(onpeak_init_interval onpeak_follow_interval offpeak_init_interval offpeak_follow_interval)) {
        if(int($self->field($field)->value) < 1) {
            $self->field($field)->add_error("Invalid interval, must be greater than 0");
        }
    }

}

1;
# vim: set tabstop=4 expandtab:
