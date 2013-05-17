package NGCP::Panel::Form::Administrator;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'id' => (type => 'Hidden');
# has_field 'reseller_id' => (type => 'PosInteger', required => 1,);
has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    not_nullable => 1,
);
has_field 'login' => (type => 'Text', required => 1,);
has_field 'md5pass' => (type => 'Password', required => 1, label => 'Password');
for (qw(is_master is_superuser is_active read_only show_passwords call_data lawful_intercept)) {
    has_field $_ => (type => 'Boolean',);
}
has_field 'save' => (type => 'Submit', element_class => [qw(btn btn-primary)],);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        reseller login md5pass is_master is_superuser is_active read_only show_passwords call_data lawful_intercept
    )],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(save)],);

sub build_render_list {
    return [qw(id fields actions)];
}

sub build_form_element_class {
    return [qw(form-horizontal)];
}

1;
