package NGCP::Panel::Form::BillingPeaktimeSpecial;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;
use DateTime;
use DateTime::Format::Strptime;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'date' => ( 
    type => 'Text',
);

has_field 'time' => (
    type => 'Compound',
);

has_field 'time.start' => (
    type => 'Text'
);

has_field 'time.end' => (
    type => 'Text'
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/date time /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub get_dates {
    my $self = shift;
    my $parsetime = DateTime::Format::Strptime->new(
        pattern => '%F %T'
    );
    my $parsetime2 = DateTime::Format::Strptime->new(
        pattern => '%F %R'
    );
    my $tmpstart = $self->value->{date} . " " . $self->value->{time}->{start};
    my $tmpend = $self->value->{date} . " " . $self->value->{time}->{end};
    my $starttime = $parsetime->parse_datetime($tmpstart)
        || $parsetime2->parse_datetime($tmpstart);
    my $endtime = $parsetime->parse_datetime($tmpend)
        || $parsetime2->parse_datetime($tmpend);
    
    return {
        start => $starttime,
        end => $endtime,
    };
}

1;

__END__

=head1 NAME

NGCP::Panel::Form::BillingPeaktimeSpecial

=head1 DESCRIPTION

Preferences Form.

=head1 METHODS

=head2 get_dates

Returns a hashref with {start => DateTime, end => DateTime} as required
by the database.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
