package NGCP::Panel::Form::TimeSet;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => (default => 'Bootstrap');

has_field 'submitid' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
);

has_field 'period' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'period.id' => (
    type => 'Hidden',
);
has_field 'period.year' => (
    type => 'Text',
    label => 'Year',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'period.month' => (
    type => 'Text',
    label => 'Month',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'period.mday' => (
    type => 'Text',
    label => 'Day of Month',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'period.wday' => (
    type => 'Text',
    label => 'Day of Week',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'period.hour' => (
    type => 'Text',
    label => 'Hour',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'period.minute' => (
    type => 'Text',
    label => 'Minute',
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'period.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);


has_field 'period_add' => (
    type => 'AddElement',
    repeatable => 'period',
    value => 'Add another period',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(submitid name period period_add)],
);

has_field 'save' => (
    type => 'Submit',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    render_list => [qw(save)],
);

sub build_render_list {
    return [qw(fields actions)];
}

sub build_form_element_class {
    return [qw(form-horizontal)];
}

#sub validate_destination {
#    my ($self, $field) = @_;
#
#    # TODO: proper SIP URI check!
#    if($field->value !~ /^sip:.+\@.+$/) {
#        my $err_msg = 'Destination must be a valid SIP URI in format "sip:user@domain"';
#        $field->add_error($err_msg);
#    }
#}

1;

# vim: set tabstop=4 expandtab:
