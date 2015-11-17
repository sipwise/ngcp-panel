package NGCP::Panel::Form::BillingPeaktimeSpecial;
use Sipwise::Base;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;
use DateTime;
use DateTime::Format::Strptime;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'start' => ( 
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['YYYY-MM-DD HH:mm:ss']
    },
    label => 'Start Date/Time',
    required => 1,
);

has_field 'end' => ( 
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['YYYY-MM-DD HH:mm:ss']
    },
    label => 'End Date/Time',
    required => 1,
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
    render_list => [qw/start end/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my $self = shift;
    my $start = $self->field('start');
    my $end = $self->field('end');
    my $parser = DateTime::Format::Strptime->new(
        pattern => '%Y-%m-%d %H:%M:%S',
    );

    my $sdate = $parser->parse_datetime($start->value);
    my ($sdt_err, $edt_err) = (0,0);
    unless($sdate) {
        $start->add_error("Invalid date format, must be YYYY-MM-DD hh:mm:ss");
        $sdt_err = 1;
    }
    my $edate = $parser->parse_datetime($end->value);
    unless($edate) {
        $end->add_error("Invalid date format, must be YYYY-MM-DD hh:mm:ss");
        $edt_err = 1;
    }

    return if $sdt_err || $edt_err;

    unless(DateTime->compare($sdate, $edate) == -1) {
        my $err_msg = 'End time must be later than start time';
        $start->add_error($err_msg);
        $end->add_error($err_msg);
    }
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

=head2 validate

Checks if start time comes before end time.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
