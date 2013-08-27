package NGCP::Panel::Form::Customer::PbxExtensionSubscriber;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_field 'ext' => (
    type => 'PosInteger',
    element_attr => { 
        class => ['ngcp_e164_sn'], 
        rel => ['tooltip'], 
        title => ['Extension Number, e.g. 101'] 
    },
    do_label => 0,
    do_wrapper => 0,
    required => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/webusername webpassword ext username password status external_id/ ],
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
