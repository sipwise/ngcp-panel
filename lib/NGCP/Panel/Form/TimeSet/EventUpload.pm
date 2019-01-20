package NGCP::Panel::Form::TimeSet::EventUpload;
use Sipwise::Base;

extends 'NGCP::Panel::Form::TimeSet::Upload';

use HTML::FormHandler::Widget::Block::Bootstrap;

has_field 'purge_existing' => (
    type => 'Boolean',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/upload purge_existing /],
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::TimeSet::EventUpload

=head1 DESCRIPTION

Preferences Form.

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
