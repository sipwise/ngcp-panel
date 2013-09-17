package NGCP::Panel::Form::Customer::PbxAdminSubscriber;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_field 'e164' => (
    type => 'Compound', 
    order => 99,
    required => 0,
    label => 'E.164 Number',
    do_label => 1,
    do_wrapper => 1,
);

has_field 'e164.cc' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_cc'], 
        rel => ['tooltip'], 
        title => ['Country Code, e.g. 1 for US or 43 for Austria'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.ac' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_ac'], 
        rel => ['tooltip'], 
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.sn' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_sn'], 
        rel => ['tooltip'], 
        title => ['Subscriber Number, e.g. 12345678'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'domain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    not_nullable => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/domain e164 display_name webusername webpassword username password status external_id/ ],
);

sub validate {
    my $self = shift;
    my $cc = $self->field('e164.cc')->value;
    my $sn = $self->field('e164.sn')->value;

    if (defined $cc && $cc ne '' && (!defined $sn || $sn eq '')) {
        my $err_msg = 'Subscriber Number required if Country Code is set';
        $self->field('e164')->add_error($err_msg);
    } elsif(defined $sn && $sn ne '' && (!defined $cc || $cc eq '')) {
        my $err_msg = 'Country Code required if Subscriber Number is set';
        $self->field('e164')->add_error($err_msg);
    }
}

1;

=head1 NAME

NGCP::Panel::Form::Subscriber

=head1 DESCRIPTION

Form to modify a subscriber.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
