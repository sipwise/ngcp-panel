package NGCP::Panel::Form::Subscriber;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::Domain;
use NGCP::Panel::Field::CustomerContract;
use NGCP::Panel::Field::Reseller;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    not_nullable => 1,
);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    not_nullable => 1,
);

has_field 'webusername' => (
    type => 'Text',
    label => 'Web Username',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The username to log into the CSC Panel'] 
    },
);

has_field 'webpassword' => (
    type => 'Password',
    label => 'Web Password',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The password to log into the CSC Panel'] 
    },
);

has_field 'e164' => (
    type => 'Compound', 
    order => 99,
    required => 0,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
);

has_field 'e164.cc' => (
    type => 'PosInteger',
    element_attr => { 
        class => ['ngcp_e164_cc'], 
        rel => ['tooltip'], 
        title => ['Country Code, e.g. 1 for US or 43 for Austria'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.ac' => (
    type => 'PosInteger',
    element_attr => { 
        class => ['ngcp_e164_ac'], 
        rel => ['tooltip'], 
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.sn' => (
    type => 'PosInteger',
    element_attr => { 
        class => ['ngcp_e164_sn'], 
        rel => ['tooltip'], 
        title => ['Subscriber Number, e.g. 12345678'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'username' => (
    type => 'Text',
    label => 'SIP Username',
    required => 1,
    noupdate => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The SIP username for the User-Agents'] 
    },
);

has_field 'domain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    not_nullable => 1,
);

has_field 'password' => (
    type => 'Password',
    label => 'SIP Password',
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The SIP password for the User-Agents'] 
    },
);

has_field 'status' => (
    type => '+NGCP::Panel::Field::SubscriberStatusSelect',
    label => 'Status',
    not_nullable => 1,
);

has_field 'administrative' => (
    type => 'Boolean',
    label => 'Administrative',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Subscriber can configure other subscribers within the Customer Account'] 
    },
);


has_field 'external_id' => (
    type => 'Text',
    label => 'External ID',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning'] 
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
    render_list => [qw/reseller contract webusername webpassword e164 username domain password status external_id administrative/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
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
