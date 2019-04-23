package NGCP::Panel::Form::TimeSet::EventAdvanced;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Block::Generic;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

my $switch_labeled_fields = [qw/byday bysetpos byyearday bymonthday byminute byweekno bysecond bymonth byhour/];

#check irka existance
#switch of the active field for the week days
#input for month days, because +1,-1 is valid input, the same switch as for week days 

#week start field support
#RDATE EXDATE support. Both are repeatables of date + time or input (datatable with button?)
#input for time and wider time picker and roller for timer - 
#implement by configuration table of the frequency and expansion/limit properties table
#validation

#event duration field support - ?
#simple inputs for checkboxes - ?
#customize button instead of select for repeat_stop - ?
#show recurrency using rrule
# + remove s from the events form name
# + fix height of the byday
# + make grey buttons for switched checkboxes
# + todo: special controls for checkboxes - select/deselect all, invert selection

has_field 'id' => (
    type => 'Hidden',
);

has_field 'comment' => (
    type => 'Text',
    label => 'Comment',
);

#dtstart
has_field 'start' => (
    type => 'Compound',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['The event or event recurrence start. Besides being the base for the recurrence, missing parameters in the final recurrence instances will also be extracted from this date. If not given, current date will be used instead.']
    },
    wrapper_class => [qw/hfh-nested-rep-block/],
);

has_field 'start.date' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Date',
    options => {
        showSecond => 'false',
    },
    default => 'now',
    no_time_picker => 1, 
    required => 1,
    do_label => 1,
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-datetimepicker-input/],
);

#dtstart time
has_field 'start.time' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Time',
    required => 0,
    default => '00:00:00',
    no_date_picker => 1, 
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-datetimepicker-input/],
);

#dtend
has_field 'end' => (
    type => 'Compound',
    label => 'Stop ',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['One time run event will last until defined datetime. If event will be defined as recurrent, end date will be used to define duration of the event iterations.']
    },
    wrapper_class => [qw/hfh-nested-rep-block/],
);


has_field 'end.date' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Date',
    options => {
        showSecond => 'false',
    },
    default => 'now',
    no_time_picker => 1, 
    required => 0,
    do_label => 1,
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-end-control ngcp-datetimepicker-input/],
);


has_field 'end.time' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Time',
    required => 0,
    default => '23:59:59',
    no_date_picker => 1, 
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-end-control ngcp-datetimepicker-input/],
);

has_field 'end.switch' => (
    type => 'Hidden',
    required => 0,
    default => 0,
    wrapper_class => [qw/ngcp-inline-control control-group/],
    tags => {
        after_element => \&switch_end_control,
    },
);

#has_field 'duration' => (
#    type => 'Compound',
#    do_label => 1,
#    do_wrapper => 1,
#    tags => {
#        controls_div => 1,
#    },
#    label_attr => {
#        rel => ['tooltip'],
#        title => ['Define duration of the event iteration. End datetime will be recountet according to entered duration.']
#    },
#    wrapper_class => [qw/hfh-nested-rep-block/],
#);

has_field 'repeat' => (
    type => 'Compound',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['Defines if event should be repeated and the frequency of the repeat.'],
    },
    wrapper_class => [qw/hfh-nested-rep-block/],
);

has_field 'repeat.interval' => (
    type => 'PosInteger',
    label => 'Every',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The interval between each iteration. For example, when \'Repeate (frequency)\' defined iteration unit as \'yearly\', an interval of \'2\' means once every two years, but with \'Repeate (frequency)\' equal to \'hourly\', it means once every two hours. The default interval is \'1\'.'],
        javascript => ' onchange="frequencySuffix(); dynamicFields();" ',
    },
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-recurrent-control ngcp-inline-control/],
);

has_field 'repeat.freq' => (
    type => 'Select',
    do_label => 0,
    required => 1,
    default => 'no',
    options_method => \&frequency_options,
    element_attr => {
        rel => ['tooltip'],
        title => ['Defines the frequency.'],
        javascript => ' onchange="dynamicFields();" ',
    },
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control/],
);

sub frequency_options {
    my %values = ('secondly' => 'Second', 'minutely' => 'Minute', 'hourly' => 'Hour', 'daily' => 'Day', 'weekly' => 'Week', 'monthly' => 'Month', 'yearly' => 'Year');
    my @freq_order = qw/daily weekly monthly yearly hourly minutely secondly/;
    my $options = [
        { value => 'no', label => 'None (run once)' },
        map { +{value => $_, label => $values{$_} }; } @freq_order
    ];
}

has_field 'repeat_stop' => (
    type => 'Compound',
    label => 'Series stop',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['Specify the limit of the recurrence.']
    },
    wrapper_class => [qw/hfh-nested-rep-block ngcp-recurrent-control/],
);

has_field 'repeat_stop.switch' => (
    type => 'Select',
    options => [ 
        { label => 'never', value=> 'never'},
        { label => 'at date', value=> 'until'},
        { label => 'after', value=> 'count'},
    ],
    do_label => 0,
    required => 0,
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    element_attr => {
        javascript => ' onchange="toggleRepeatStopControl();" ',
    },
    wrapper_class => [qw/ngcp-recurrent-control ngcp-inline-control/],
);

has_field 'repeat_stop.until_date' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    #label => '',
    options => {
        showSecond => 'false',
    },
    default => 'now',
    no_time_picker => 1, 
    required => 0,
    do_label => 0,
    do_wrapper => 1,
    tags => {
        inline => 1,
    },
    element_attr => {
        rel => ['tooltip'],
        title => ['If a recurrence instance happens to be the same as the given \'until\' value, this will be the last occurrence. \'until\' shouldn\'t be defined together with \'Count\'.']
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-recurrent-control ngcp-datetimepicker-input ngcp-repeatstop-until/],
);

has_field 'repeat_stop.until_time' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => '',
    required => 0,
    default => '23:59:59',
    no_date_picker => 1, 
    do_wrapper => 1,
    do_label => 0,
    tags => {
        inline => 1,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-recurrent-control ngcp-datetimepicker-input ngcp-repeatstop-until/],
);


has_field 'repeat_stop.count' => (
    type => 'PosInteger',
    do_label => 0,
    default => '1',
    element_attr => {
        rel => ['tooltip'],
        title => ['How many occurrences will be generated. Valid value is a positive integer. Can\'t be defined together with \'until\'.'],
    },
    tags => {
        inline => 1,
        #before_element => \&show_repeat_stop_switch,
    },
    wrapper_class => [qw/ngcp-inline-control ngcp-recurrent-control ngcp-repeatstop-count/],
);


has_field 'byhour' => (
    type => 'Multiple', # Select
    widget => 'CheckboxGroup',
    label => 'By hour',
    min_value => 0,
    max_value => 23,
    options => [
        map { +{value => $_, label => $_}; } (0..23)
    ],
    label_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 23, i.e. 1,3,23. Means the hours to apply the recurrence to.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control ngcp-60-checkboxes/],
);

#byweekday
has_field 'byday' => (
    type => 'Compound',
    label => 'By week day',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer (0 == Monday), a sequence of integers, one of the weekday constants (MO, TU, etc), or a sequence of these constants. When given, these variables will define the weekdays where the recurrence will be applied.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control/],#hfh-nested-rep-block 
);

has_field 'byday.simple' => (
    #type => 'Text', # ((\+|-)?\d*(MO|TU|WE|TH|FR|SA|SO),?)+
    type => 'Multiple', # Select
    widget => 'CheckboxGroup',
    required => '0',
    label => 'By week day',
    options => [
        map { +{value => substr($_,0,2), label => substr($_,0,2)}; } (qw/MON TUE WED THU FRI SAT SUN/)
    ],
    label_attr => {
        rel => ['tooltip'],
        title => ['Defines week days to apply the recurrence to.']
    },
    # example: 5FR (means fifth friday)
    wrapper_class => [qw/ngcp-recurrent-control ngcp-7-checkboxes/],
);

has_field 'byday.advanced' => (
    type => 'Text', # ((\+|-)?\d*(MO|TU|WE|TH|FR|SA|SU),?)+
    required => '0',
    label => 'By week day number',
    label_attr => {
        rel => ['tooltip'],
        title => ['It\'s possible to use an argument n for the weekday instances, which will mean the nth occurrence of this weekday in the period. For example, with \'Repeat\' equal to \'monthly\', or with \'Repeat\' equal to \'yearly\' and \'bymonth\', using  \'+1FR\' in \'By day\' will specify the first friday of the month where the recurrence happens. Format is: (\+|-)?\d*(MO|TU|WE|TH|FR|SA|SU).']
    },
    # example: 5FR (means fifth friday)
    wrapper_class => [qw/ngcp-recurrent-control/],
);


has_field 'bymonth' => (
    #type => '+NGCP::Panel::Field::IntegerList',
    type => 'Multiple', # Select
    widget => 'CheckboxGroup',
    label => 'By month',
    options_method => \&month_options,
    min_value => 1,
    max_value => 12,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the months to apply the recurrence to. January is equal to 1.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control ngcp-6-checkboxes/],
);

sub month_options {
    my @values = (qw/January February March April May June July August September October November December/);
    my $options = [
        map { +{value => $_ + 1, label => ucfirst($values[$_]) }; } keys @values
    ];
}

has_field 'bymonthday' => (
    type => 'Compound',
    label => 'By month day',
    do_label => 1,
    do_wrapper => 1,
    tags => {
        controls_div => 1,
    },
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the month days to apply the recurrence to.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control/],#hfh-nested-rep-block 
);

has_field 'bymonthday.simple' => (
    #type => '+NGCP::Panel::Field::IntegerList',
    type => 'Multiple', # Select
    required => '0',
    widget => 'CheckboxGroup',
    label => 'By month day',
    options => [
        map { +{value => $_, label => $_}; } (1..31)
    ],
    label_attr => {
        rel => ['tooltip'],
        title => ['Sequence of positive integers, meaning the month days to apply the recurrence to.']
    },
    wrapper_class => [qw/ngcp-recurrent-control ngcp-32-checkboxes/],
);

has_field 'bymonthday.advanced' => (
    type => '+NGCP::Panel::Field::IntegerList',
    required => '0',
    label => 'By month day number',
    min_value => 1,
    max_value => 31,
    plusminus => 1,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of positive and/or negative integers, meaning the month days to apply the recurrence to.']
    },
    wrapper_class => [qw/ngcp-recurrent-control/],
);


has_field 'bysetpos' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By set position',
    min_value => 1,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, positive or negative. Each given integer will specify an occurrence number, corresponding to the nth occurrence of the rule inside the frequency period. For example, a \'By set position\' of \'-1\' if combined with a \'1 Month\' repeat frequency, and a byweekday of (\'Mo\', \'Tu\', \'We\', \'Th\', \'Fr\'), will result in the last work day of every month.'],
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control/],
);

has_field 'byweekno' => (
    #type => '+NGCP::Panel::Field::IntegerList',
    type => 'Multiple', # Select
    widget => 'CheckboxGroup',
    label => 'By week number',
    options => [
        map { +{value => $_, label => $_}; } (1..53)
    ],
    min_value => 1,
    max_value => 53,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the week numbers to apply the recurrence to. Week numbers have the meaning described in ISO8601, that is, the first week of the year is that containing at least four days of the new year.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control ngcp-60-checkboxes/],
);

has_field 'byyearday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By year day',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the year days to apply the recurrence to.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control/],
);

has_field 'bysecond' => (
    label => 'By second',
    type => 'Multiple', # Select
    required => '0',
    widget => 'CheckboxGroup',
    options => [
        map { +{value => $_, label => $_}; } (0..59)
    ],
    min_value => 0,
    max_value => 59,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the seconds to apply the recurrence to. Number(s) in set should be between 0 and 59.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control ngcp-60-checkboxes/],
);

has_field 'byminute' => (
    label => 'By minute',
    type => 'Multiple', # Select
    required => '0',
    widget => 'CheckboxGroup',
    options => [
        map { +{value => $_, label => $_}; } (0..59)
    ],
    min_value => 0,
    max_value => 59,
    label_attr => {
        rel => ['tooltip'],
        title => ['If given, it must be either an integer, or a sequence of integers, meaning the seconds to apply the recurrence to. Number(s) in set should be between 0 and 59.']
    },
    wrap_label_method => \&wrap_label_field_switch,
    wrapper_class => [qw/ngcp-recurrent-control ngcp-60-checkboxes/],
);

has_field 'label_switch' => (
    type => 'Compound',
    label => '',
    do_label => 0,
    do_wrapper => 0,
    tags => {
        controls_div => 0,
    },
    #wrapper_class => [qw/ngcp-hidden/],
);

foreach (@$switch_labeled_fields) {
    has_field 'label_switch.'.$_ => (
        type => 'Hidden',
    );
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    #duration
    render_list => [qw/id comment start end repeat repeat_stop byhour byday bymonth bymonthday bysetpos byweekno byyearday bysecond byminute label_switch/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

#Cannot assign a value to a read-only accessor at reader HTML::FormHandler::Field::wrap_label_method
#this is why we need additional field label_switch and can't use update_fields just to add switch sign
#sub update_fields {
#    my ($self) = @_;
#    my ($c) = $self->ctx;
#    return unless $c;
#
#    foreach my $field (@$switch_labeled_fields) {
#        $self->field($field)->wrap_label_method(\&wrap_label_field_switch);
#    }
#}

sub switch_end_control {
    my ($self) = @_;
    my $form = $self->form;
    my $ctx = $form->ctx;
    my $element = NGCP::Panel::Block::Generic->new( 
        c => $ctx, 
        template => 'timeset/switch_end_control.tt', 
        form => $form );
    return $element->render({ field => $self });
}

sub wrap_label_field_switch {
    my ($self) = @_;
    my $form = $self->form;
    my $ctx = $form->ctx;
    my $element = NGCP::Panel::Block::Generic->new( 
        c => $ctx, 
        template => 'timeset/switch_field_label.tt', 
        form => $form );
    return $element->render({ field => $self });
}

sub custom_get_values {
    my ($self, $params) = @_;
    my $fif = $self->values;
    my $values = {};

    $values->{start} = join('T', @{$fif->{start}}{qw/date time/});

    if ($fif->{end} && $fif->{end}->{switch}) {
        $values->{end} = join('T', @{$fif->{end}}{qw/date time/});
    } else {
        $values->{end} = '0000-00-00 00:00:00';
    }

    if ($fif->{repeat}->{freq} ne 'no') {
        $values->{freq} = $fif->{repeat}->{freq};
        $values->{interval} = $fif->{repeat}->{interval};
    } else {
        $values->{freq} = undef;
        $values->{interval} = undef;
    }

    if ($fif->{repeat_stop}->{switch} ne 'never') {
        if ($fif->{repeat_stop}->{switch} eq 'count') {
            $values->{count} = $fif->{repeat_stop}->{count};
            $values->{until} = undef;
        } else {
            $values->{until} = join('T', @{$fif->{repeat_stop}}{qw/until_date until_time/});
            $values->{count} = undef;
        }
    } else {
        $values->{count} = undef;
        $values->{until} = undef;
    }

    my @simple_fields = qw/comment bysetpos byyearday/;
    @{$values}{@simple_fields} = @{$fif}{@simple_fields};

    my @join_fields = qw/bymonthday byminute byweekno bysecond bymonth byhour/;
    foreach my $join_field (@join_fields) {
        $fif->{$join_field} 
            and ref $fif->{$join_field} eq 'ARRAY' 
            and $values->{$join_field} = join(',',@{$fif->{$join_field}});
    }

    if ($fif->{byday}) {
        if ($fif->{byday}->{advanced}) {
            $values->{byday} = $fif->{byday}->{advanced};
        } elsif ($fif->{byday}->{simple}) {
            $values->{byday} = join(',', @{$fif->{byday}->{simple}});
        }
    }

    foreach my $switched_field (@$switch_labeled_fields) {
        if (!$fif->{label_switch}->{$switched_field}) {
            $values->{$switched_field} = undef;
        }
    }

    return $values;
}

sub custom_set_values {
    my ($self, $values) = @_;
    my $fif;
    @{$fif->{start}}{qw/date time/} = split(/[T ]/, $values->{start});

    if ($values->{end} && $values->{end} ne '0000-00-00 00:00:00') {
        @{$fif->{end}}{qw/date time/} = split(/[T ]/, $values->{end});
        $fif->{end}->{switch} = 1;
    } else {
        $fif->{end}->{switch} = 0;
    }

    if ($values->{freq}) {
        $fif->{repeat}->{freq} = $values->{freq};
        $fif->{repeat}->{interval} = $values->{interval};
    } else {
        $fif->{repeat}->{freq} = 'no';
    }

    if ($values->{count}) {
        $fif->{repeat_stop}->{switch} = 'count';
        $fif->{repeat_stop}->{count} = $values->{count};
    } elsif ($values->{until}) {
        $fif->{repeat_stop}->{switch} = 'until';
        @{$fif->{repeat_stop}}{qw/until_date until_time/} = split(/[T ]/, $values->{until});
    } else {
        $fif->{repeat_stop}->{switch} = 'never';
    }

    my @simple_fields = qw/comment bysetpos byyearday/;
    @{$fif}{@simple_fields} = @{$values}{@simple_fields};

    my @join_fields = qw/bymonthday byminute byweekno bysecond bymonth byhour/;
    foreach my $join_field (@join_fields) {
        if ($values->{$join_field}) {
            $fif->{$join_field} = [split(/,/, $values->{$join_field})];
        }
    }
    if ($values->{byday}) {
        if ($values->{byday} =~ /^(?:(?:MO|TU|WE|TH|FR|SA|SU),?)+$/) {#
            $fif->{byday}->{simple} = [split(/,/, $values->{byday})];
        } else {
            $fif->{byday}->{advanced} = $values->{byday};
        }
    }
    #really, javascript will care about it
    foreach my $switched_field (@$switch_labeled_fields) {
        if ($values->{$switched_field}) {
            $fif->{label_switch}->{$switched_field} = 1;
        }
    }

    return $fif;
}

1;

# vim: set tabstop=4 expandtab:
