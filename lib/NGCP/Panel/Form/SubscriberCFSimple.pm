package NGCP::Panel::Form::SubscriberCFSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'id' => (type => 'Hidden');

has_field 'destination' => (type => 'Text', required => 1,);
has_field 'save' => (type => 'Submit', element_class => [qw(btn btn-primary)],);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(destination)],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(save)],);

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
