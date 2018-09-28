package NGCP::Panel::Form::TimeSet::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
);

has_field 'times' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of time definitions with a number of optional and mandatory keys.']
    },
);

has_field 'times.id' => (
    type => 'Hidden',
);

has_field 'times.start' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Start',
    required => 1,
);

has_field 'times.end' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'End',
);

has_field 'times.freq' => (
    type => 'Select',
    label => 'Frequency',
    options => [
        map { +{value => $_, label => $_}; } (qw/secondly minutely hourly daily weekly monthly yearly/)
    ],
);

has_field 'times.until' => (
    label => 'Until',
    type => '+NGCP::Panel::Field::DateTimePicker',
    element_attr => {
        rel => ['tooltip'],
        title => ['Can\'t be defined together with "Count".']
    },
);

has_field 'times.count' => (
    type => 'PosInteger',
    label => 'Count',
    element_attr => {
        rel => ['tooltip'],
        title => ['Valid value is a positive integer. Can\'t be defined together with "Until".']
    },
);

has_field 'times.interval' => (
    type => 'PosInteger',
    label => 'Interval',
    element_attr => {
        rel => ['tooltip'],
        title => ['Valid value is a positive integer.']
    },
);

has_field 'times.bysecond' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By second',
    min_value => 0,
    max_value => 59,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 59, i.e. 1,3,59.']
    },
);

has_field 'times.byminute' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By minute',
    min_value => 0,
    max_value => 59,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 59, i.e. 1,3,59.']
    },
);

has_field 'times.byhour' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By hour',
    min_value => 0,
    max_value => 23,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 23, i.e. 1,3,23.']
    },
);

has_field 'times.byday' => (
    type => 'Text', # (\+|-)?\d*(MO|DI|MI|DO|FR|SA|SU)
    label => 'By day',
    element_attr => {
        rel => ['tooltip'],
        title => ['Value format is [+|-][NUMBER](MO|DI|MI|DO|FR|SA|SU). Example: 5FR (means fifth friday).']
    },
    # example: 5FR (means fifth friday)
);

has_field 'times.bymonthday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month day',
    min_value => 1,
    max_value => 31,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 31, i.e. 1,3,31.']
    },
);

has_field 'times.byyearday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By year day',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 366, i.e. 1,3,366.']
    },
);

has_field 'times.byweekno' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By week number',
    min_value => 1,
    max_value => 53,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 53, i.e. 1,3,53.']
    },
);

has_field 'times.bymonth' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month',
    min_value => 1,
    max_value => 12,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 12, i.e. 1,3,12.']
    },
);

has_field 'times.bysetpos' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By set position',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 366, i.e. 1,3,366.']
    },
);

has_field 'times.comment' => (
    type => 'Text',
    label => 'Comment',
);

has_field 'times.rm' => (
    type => 'RmElement',
    value => 'Remove Set',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'times_add' => (
    type => 'AddElement',
    repeatable => 'times',
    value => 'Add another Set',
    element_class => [qw/btn btn-primary pull-right/],
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
    render_list => [qw/id name times times_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my ($self, $field) = @_;
    my $c = $self->ctx;
    return unless $c;
    my $schema = $c->model('DB');

    my $name = $self->field('name')->value;
    my $reseller_id;
    #Todo: to some utils?
    if ($c->user->roles eq 'admin') {
        if ($self->field('reseller')) {
            $reseller_id = $self->field('reseller')->value;
        } elsif($c->stash->{reseller}) { #strange, reseller interface keeps rs as reseller, not reseller_rs
            $reseller_id = $c->stash->{reseller}->first->id;
        }
    } else {
        $reseller_id = $c->user->reseller_id
    }
    unless ($reseller_id) {
        #we shouldn't get here
        $self->field('name')->add_error($c->loc('Unknow reseller'));
    }
    #/todo
    my $existing_item = $schema->resultset('voip_time_sets')->find({
        name => $name,
    });
    my $current_item = $c->stash->{timeset_rs};
    if ($existing_item && (!$current_item || $existing_item->id != $current_item->id)) {
        $self->field('name')->add_error($c->loc('This name already exists'));
    }
}
1;

# vim: set tabstop=4 expandtab:
