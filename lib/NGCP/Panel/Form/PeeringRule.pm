package NGCP::Panel::Form::PeeringRule;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'callee_prefix' => ( 
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Callee prefix, eg: 43']
    },
);

has_field 'callee_pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    element_attr => {
        rel => ['tooltip'],
        title => [q!A POSIX regex matching against the full Request-URI (e.g. '^sip:.+@example\.org$' or '^sip:431')!]
    },
);

has_field 'caller_pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    element_attr => {
        rel => ['tooltip'],
        title => [q!A POSIX regex matching against 'sip:user@domain' (e.g. '^sip:.+@example\.org$' matching the whole URI, or '999' matching if the URI contains '999')!]
    },
);

has_field 'description' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['string, rule description']
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
    render_list => [qw/ callee_prefix callee_pattern caller_pattern description /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::PeeringRule

=head1 DESCRIPTION

-

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
