package NGCP::Panel::Form::PeeringGroup;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden'
);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::Contract',
    label => 'Contract',
    not_nullable => 1,
);


has_field 'name' => (
    type => 'Text',
    required => 1,
);

has_field 'priority' => (
    type => 'IntRange',
    range_start => '1',
    range_end => '9',
);

has_field 'description' => (
    type => 'Text',
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
    render_list => [qw/id contract name priority description/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub custom_get_values {
    my ($self) = @_;
    my $fif = $self->fif;
    my $hashvalues = {
        name => $fif->{name},
        priority => $fif->{priority},
        description => $fif->{description},
        peering_contract_id => $fif->{'contract.id'},
    };
    return $hashvalues;
}

=head1 NAME

NGCP::Panel::Form::PeeringGroup

=head1 DESCRIPTION

Form to edit/create a voip_peer_group(s).

=head1 METHODS

=head2 custom_get_values

Returns the values in a form that is understood by the database. The returned
field names are: name, priority, description, peering_contract_id

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
# vim: set tabstop=4 expandtab:
