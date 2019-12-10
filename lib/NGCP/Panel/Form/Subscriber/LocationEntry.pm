package NGCP::Panel::Form::Subscriber::LocationEntry;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'contact' => (
    type => 'Text',
    label => 'Contact URI',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The SIP URI pointing to the current contact of the subscriber. Should be a full sip uri, sip:user@ip:port.']
    },
);

has_field 'path' => (
    type => 'Text',
    label => 'LB path',
    readonly => 1,#we will not take direct path, only socket
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Readonly lb/path field. Composed from "socket" and internal configuration information.']
    },
);

has_field 'q' => (
    type => 'Float',
    label => 'Priority (q-value)',
    required => 1,
    range_start => 0,
    range_end => 1,
    decimal_symbol => '.',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact priority for serial forking (float value, higher is stronger) between 0 and 1.00']
    },
    #validate_method => \&validate_q,
);

has_field 'socket' => (
    type => '+NGCP::Panel::Field::Select',
    label => 'Outbound socket',
    required => 0,
    options_method => \&build_socket_options,
    element_attr => {
        rel => ['tooltip'],
        title => ['Points to the LB interface from which the incoming calls to this registration should be sent out.']
    },
    translate => 0
);

sub build_socket_options {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return unless $c;
    my $outbound_socket_rs = $c->model('DB')->resultset('voip_preferences_enum')->search_rs({
        'preference.attribute' => 'outbound_socket'
    },{
        join => 'preference',
    });
    my @options = ();
    foreach my $s($outbound_socket_rs->all) {
        #default in db is null (undefined), so we will void FormHandler warnings
        my $value = $s->value // '';
        $value =~s/udp:/sip:/;
        push @options, { label => $s->label, value => $value };
    }
    return \@options;
}

sub validate_q {
    my ($self,$field) = @_;
    if(($field->value < 0) || ($field->value > 1)){
        $field->add_error('Value of "q" must be a float value between 0 and 1');
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

__END__

=head1 NAME

NGCP::Panel::Form::Subscriber::LocationEntry

=head1 DESCRIPTION

A helper to manipulate the registered API subscriber form

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:

