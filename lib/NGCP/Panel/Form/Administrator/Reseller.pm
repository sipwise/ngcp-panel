package NGCP::Panel::Form::Administrator::Reseller;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'login' => (type => 'Text', required => 1, minlength => 5, maxlength => 31);
has_field 'password' => (type => 'Password', required => 1, label => 'Password');
for (qw(is_active show_passwords call_data billing_data)) {
    has_field $_ => (type => 'Boolean', default => 1);
}
for (qw(is_master read_only)) {
    has_field $_ => (type => 'Boolean',);
}
has_field 'save' => (type => 'Submit', element_class => [qw(btn btn-primary)],);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        login password is_master is_active read_only show_passwords call_data billing_data
    )],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(save)],);

sub validate_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field);
}

1;
