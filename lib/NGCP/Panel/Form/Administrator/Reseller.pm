package NGCP::Panel::Form::Administrator::Reseller;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'login' => (type => 'Text', required => 1, minlength => 5, maxlength => 31, default_method => \&_set_default);
has_field 'password' => (type => 'Password', required => 1, label => 'Password');
has_field 'email' => (type => 'Email', required => 0, label => 'Email', maxlength => 255);
for (qw(is_active show_passwords call_data billing_data
        is_master is_ccare read_only can_reset_password)) {
    has_field $_ => (type => 'Boolean', default_method => \&_set_default);
}
has_field 'save' => (type => 'Submit', element_class => [qw(btn btn-primary)],);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        login password email is_master is_active read_only show_passwords call_data billing_data can_reset_password
    )],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(save)],);

sub _set_default {
    my ($field) = @_;
    my $form  = $field->form;
    my $c     = $form->ctx;

    if (grep { $field->name eq $_ }
        qw(is_active show_passwords call_data billing_data)) {

        $field->default(1);
    }

    if (_check_inactive($field, $field->name)) {
        $field->inactive(1);
    }
}

sub _check_inactive {
    my ($self, $field_name) = @_;
    my $form = $self->form;
    my $c    = $form->ctx;

    if ( ! $form->field('role')) {
        if ($field_name eq 'role_id' && $c->user->roles eq 'ccareadmin') {
            return 1;
        }
        if ((grep { $field_name eq $_ }
            qw(is_active is_master read_only
               show_passwords call_data billing_data role_id)) && $c->state &&
            $c->state->login eq $c->user->login) {

            return 1;
        }
    }

    return;
}

sub field_list {
    my $self = shift;

    return [
        role_id => {
            type => 'Select',
            options => [
                $self->_acl_role_select_options()
            ],
            required => 0,
            default_method => \&_set_default,
            element_attr => {
                rel => ['tooltip'],
                title => ['Role']
            },
            label => 'Role',
        }
    ];
}

sub validate_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field, utf8 => 0);
}

sub _acl_role_select_options {
    my $self = shift;
    my $c = $self->form->ctx;

    return (
        map {+{ value => $_->id, label => $_->role }}
            $c->model('DB')->resultset('acl_roles')->search(undef, {order_by => 'role'})->all
    );
}

1;
