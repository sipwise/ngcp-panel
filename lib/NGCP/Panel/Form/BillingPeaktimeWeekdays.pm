package NGCP::Panel::Form::BillingPeaktimeWeekdays;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

has_field 'weekday' => (
    type => 'Hidden',
);

has_field 'start' => ( 
    type => 'Text',
    do_label => 0,
    do_wrapper => 0,
);

has_field 'end' => (
    type => 'Text',
    do_label => 0,
    do_wrapper => 0,
);

has_field 'add' => (
    type => 'Submit',
    value => 'Add',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
    do_wrapper => 0,
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::BillingPeaktimeWeekdays

=head1 DESCRIPTION

Preferences Form.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
