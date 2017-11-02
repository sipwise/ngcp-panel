package NGCP::Panel::Form::Administrator::Admin;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'NGCP::Panel::Form::Administrator::Reseller';

use NGCP::Panel::Utils::Admin;

for (qw(is_superuser lawful_intercept)) {
    has_field $_ => (type => 'Boolean',);
}
has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    validate_when_empty => 1,
);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        reseller login password is_superuser is_master is_active read_only show_passwords call_data billing_data lawful_intercept
    )],
);

sub field_list {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);
    if($c->stash->{administrator}->login eq NGCP::Panel::Utils::Admin::get_special_admin_login) {
        foreach my $field ($self->fields){
            my $field_name = $field->name;
            if('is_active' ne $field_name 
                && 'save' ne $field_name
                && 'submitid' ne $field_name){
                $self->field($field_name)->inactive(1);
            }
        }
    }
}

1;
