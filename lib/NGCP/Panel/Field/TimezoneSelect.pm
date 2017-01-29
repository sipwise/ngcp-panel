package NGCP::Panel::Field::TimezoneSelect;
use Moose;
use HTML::FormHandler::Moose;
use DateTime::TimeZone;
extends 'HTML::FormHandler::Field::Compound';

has_field 'name' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Timezone',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/timezone_ajax',
    table_titles => ['Name'],
    table_fields => ['name'],
);

sub validate {
    my $self = shift;
    my $value = $self->value;
    if (ref $value && exists $value->{name}) {
        $value = $value->{name};
    } else {
        $self->add_error(
            sprintf 'Invalid validation of unparsed input: %s', $value);
        return;
    }

    unless(grep { /^\Q$value\E$/ } DateTime::TimeZone->all_names) {
        $self->add_error(sprintf 'Invalid timezone name: %s', $value);
    }
    return;
}


no Moose;
1;
