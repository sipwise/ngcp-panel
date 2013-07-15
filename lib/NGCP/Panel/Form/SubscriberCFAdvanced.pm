package NGCP::Panel::Form::SubscriberCFAdvanced;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';
#with 'HTML::FormHandler::Render::RepeatableJs';

has '+widget_wrapper' => (default => 'Bootstrap');

has_field 'submitid' => (
    type => 'Hidden',
);

has_field 'active_callforward' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'active_callforward.destination_set' => (
    type => '+NGCP::Panel::Field::SubscriberDestinationSet',
    label => 'Destination Set',
    wrapper_class => [qw/hfh-rep-field/],

);

has_field 'active_callforward.time_set' => (
    type => '+NGCP::Panel::Field::SubscriberTimeSet',
    label => 'during Time Set',
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'active_callforward.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);


has_field 'callforward_controls_add' => (
    type => 'AddElement',
    repeatable => 'active_callforward',
    value => 'Add more',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(submitid active_callforward callforward_controls_add)],
);

has_field 'cf_actions' => (
    type => 'Compound',
    do_label => 0,
    do_wrapper => 1,
    wrapper_class => [qw(row pull-right)],
);


has_field 'cf_actions.save' => (
    type => 'Button',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
    wrapper_class => [qw(pull-right)],
);

has_field 'cf_actions.simple' => (
    type => 'Button', 
    do_label => 0,
    value => 'Simple View',
    element_class => [qw(btn btn-tertiary)],
    wrapper_class => [qw(pull-right)],
);

has_field 'cf_actions.edit_time_sets' => (
    type => 'Button', 
    do_label => 0,
    value => 'Manage Time Sets',
    element_class => [qw(btn btn-tertiary)],
    wrapper_class => [qw(pull-right)],
);

has_field 'cf_actions.edit_destination_sets' => (
    type => 'Button', 
    do_label => 0,
    value => 'Manage Destination Sets',
    element_class => [qw(btn btn-tertiary)],
    wrapper_class => [qw(pull-right)],
);



has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    #render_list => [qw(save simple edit_time_sets edit_destination_sets)],
    render_list => [qw(cf_actions)],
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
