package NGCP::Panel::Form::Peering::InboundRule;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'field' => ( 
    type => 'Select',
    label => 'Match Field',
    options => [
        { value => 'from_user', label => 'From-User' },
        { value => 'from_domain', label => 'From-Domain' },
        { value => 'from_uri', label => 'From-URI' },
        { value => 'to_user', label => 'To-User' },
        { value => 'to_domain', label => 'To-Domain' },
        { value => 'to_uri', label => 'To-URI' },
        { value => 'ruri_user', label => 'RURI-User' },
        { value => 'ruri_domain', label => 'RURI-Domain' },
        { value => 'ruri_uri', label => 'RURI-URI' },
        { value => 'pai_user', label => 'PAI-User' },
        { value => 'pai_domain', label => 'PAI-Domain' },
        { value => 'pai_uri', label => 'PAI-URI' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The field of the inbound SIP message to match the pattern against']
    },
);

has_field 'pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    max_length => 1023,
    element_attr => {
        rel => ['tooltip'],
        title => [q!A POSIX regex matching against the specified field (e.g. '^sip:.+@example\.org$' or '^sip:431') when matching against a full URI!]
    },
);

has_field 'reject_code' => (
    type => 'PosInteger',
    not_nullable => 0,
    range_start => 400,
    range_end => 699,
    element_attr => {
        rel => ['tooltip'],
        title => ['If specified, the call is rejected if the source IP of the request is found in a peering server of the group, but the given pattern does not match; Range of 400-699']
    },
);

has_field 'reject_reason' => (
    type => 'Text',
    not_nullable => 0,
    max_length => 64,
    element_attr => {
        rel => ['tooltip'],
        title => ['If reject code is specified and the call is rejected, the reason in the response is taken from this value']
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    label => 'Enabled',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Rule enabled state.'],
    },
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
    render_list => [qw/field pattern reject_code reject_reason enabled/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;

    my $reason = $self->field('reject_reason');
    my $code = $self->field('reject_code');

    if(defined $code->value && !defined $reason->value) {
        return $reason->add_error($c->loc('reject reason must be filled if reject code is filled'));
    } elsif(defined $reason->value && !defined $code->value) {
        return $code->add_error($c->loc('reject code must be filled if reject reason is filled'));
    }

    return;
}

1;

