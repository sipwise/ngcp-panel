package NGCP::Panel::Form::Subscriber::RegisteredAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+use_fields_for_input_without_param' => ( default => 1 );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber the contact belongs to.']
    },
);

has_field 'contact' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The SIP URI pointing to the current contact of the subscriber.']
    },
);

has_field 'expires' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The expire timestamp of the registered contact.']
    },
);

has_field 'q' => (
    type => 'Float',
    required => 1,
    range_start => -1,
    range_end => 1,
    decimal_symbol => '.',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The priority (q-value) of the registration.']
    },
    #validate_method => \&validate_q,
);

has_field 'nat' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The registered contact is detected as behind NAT.']
    },
);
sub validate_q {
    my ($self,$field) = @_;
    if(($field->value < -1) || ($field->value > 1)){
        $field->add_error('Value of "q" must be a float value between -1 and 1'); 
        return;
    }
    return 1;
}
=pod
sub validate {
    my $self = shift;
    my $attach = $self->field('attach')->value;
    my $delete = $self->field('delete')->value;
    if($delete && !$attach) {
        $self->field('attach')->add_error('Must be set if delete is set');
    }
}
=cut


1;
# vim: set tabstop=4 expandtab:
