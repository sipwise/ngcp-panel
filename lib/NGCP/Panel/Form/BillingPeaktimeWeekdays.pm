package NGCP::Panel::Form::BillingPeaktimeWeekdays;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
use DateTime;
use DateTime::Format::Strptime;

has '+widget_wrapper' => ( default => 'Bootstrap' );

has_field 'weekday' => (
    type => 'Hidden',
);

has_field 'start' => ( 
    type => 'Text',
    do_label => 0,
    do_wrapper => 1,
    element_attr => {
        class => ['ngcp_time_range'],
        rel => ['tooltip'],
        title => ['The start time in format hh:mm:ss']
    },
    wrapper_class => ['ngcp_field_inline'],
);

has_field 'end' => (
    type => 'Text',
    do_label => 0,
    do_wrapper => 1,
    element_attr => {
        class => ['ngcp_time_range'],
        rel => ['tooltip'],
        title => ['The end time in format hh:mm:ss']
    },
    wrapper_class => ['ngcp_field_inline'],
);

has_field 'add' => (
    type => 'Submit',
    value => 'Add',
    element_class => [qw/btn btn-primary pull-right/],
    do_label => 0,
    do_wrapper => 0,
);

sub validate {
    my $self = shift;

    my $parsetime  = DateTime::Format::Strptime->new(pattern => '%T');
    my $parsetime2 = DateTime::Format::Strptime->new(pattern => '%R');
    my $start = $parsetime->parse_datetime($self->field('start')->value)
            || $parsetime2->parse_datetime($self->field('start')->value);
    my $end = $parsetime->parse_datetime($self->field('end')->value)
          || $parsetime2->parse_datetime($self->field('end')->value);

    if ($end < $start) {
        my $err_msg = 'Start time must be later than end time.';
        $self->field('start')->add_error($err_msg);
        $self->field('end')->add_error($err_msg);
    }
}

1;

__END__

=head1 NAME

NGCP::Panel::Form::BillingPeaktimeWeekdays

=head1 DESCRIPTION

Preferences Form.

=head1 METHODS

=head2 validate

Checks if start time comes before end time.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
