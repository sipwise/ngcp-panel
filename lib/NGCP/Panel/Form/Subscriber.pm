package NGCP::Panel::Form::Subscriber;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::Domain;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'webusername' => (
    type => 'Text',
    label => 'Web Username',
);

has_field 'webpassword' => (
    type => 'Password',
    label => 'Web Password',
);

has_field 'e164' => (
    type => 'Compound', 
    order => 99,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
);

has_field 'e164.cc' => (
    type => 'PosInteger',
    label => 'cc:',
    element_attr => { class => ['ngcp_e164_cc'] },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.ac' => (
    type => 'PosInteger',
    label => 'ac:',
    element_attr => { class => ['ngcp_e164_ac'] },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'e164.sn' => (
    type => 'PosInteger',
    label => 'sn:',
    element_attr => { class => ['ngcp_e164_sn'] },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'sipusername' => (
    type => 'Text',
    label => 'SIP Username',
    noupdate => 1,
);

has_field 'sipdomain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    not_nullable => 1,
);

has_field 'sippassword' => (
    type => 'Password',
    label => 'SIP Password',
);

has_field 'administrative' => (
    type => 'Boolean',
    label => 'Administrative',
);


has_field 'external_id' => (
    type => 'Text',
    label => 'External ID',
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
    render_list => [qw/webusername webpassword e164 sipusername sipdomain sippassword external_id administrative/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

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
