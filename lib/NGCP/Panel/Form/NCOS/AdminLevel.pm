package NGCP::Panel::Form::NCOS::AdminLevel;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::NCOS::ResellerLevel';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller level mode description/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::NCOSLevel

=head1 DESCRIPTION

Form to modify a billing.ncos_levels row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
