package NGCP::Panel::Form::SubscriberCFSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'submitid' => (
    type => 'Hidden',
);

has_field 'destination' => (
    type => 'Text', 
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either a number (e.g. &ldquo;431234&rdquo;), a SIP user (e.g. &ldquo;peter&rdquo; or a full SIP URI (e.g. &ldquo;sip:peter@example.org&rdquo;)']
    },
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

has_field 'cf_actions.advanced' => (
    type => 'Button', 
    do_label => 0,
    value => 'Advanced View',
    element_class => [qw(btn btn-tertiary)],
    wrapper_class => [qw(pull-right)],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(submitid destination)],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(cf_actions)],);

sub build_render_list {
    return [qw(id fields actions)];
}

sub build_form_element_class {
    return [qw(form-horizontal)];
}

sub validate_destination {
    my ($self, $field) = @_;

    # TODO: proper SIP URI check!
    if($field->value !~ /^sip:.+\@.+$/) {
        my $err_msg = 'Destination must be a valid SIP URI in format "sip:user@domain"';
        $field->add_error($err_msg);
    }
}
1;

# vim: set tabstop=4 expandtab:
