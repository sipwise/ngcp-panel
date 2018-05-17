package NGCP::Panel::Form::Device::Preference;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'NGCP::Panel::Render::RepeatableJs';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Utils::Preferences;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden'
);

has_field 'attribute' => (
    type => 'Text',
    required => 1,
    label => 'Name',
    maxlength => '31',
    element_attr => {
        rel => ['tooltip'],
        title => ['Name will be prefixed with double underscore.']
    },
);

has_field 'label' => (
    type => 'Text',
    maxlength => '255',
    required => 1,
    label => 'Label',
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    label => 'Description',
);

has_field 'fielddev_pref' => (
    type => 'Boolean',
    default => 1,
    label => 'Override on deployed device',
);

has_field 'max_occur' => (
    type => 'Boolean',
    default => '0',
    label => 'Only one is allowed.',
);

has_field 'data_type' => (
    type => 'Select',
    required => 1,
    label => 'Data type',
    options => [
        { value => '',        label => 'none' },
        { value => 'boolean', label => 'Boolean' },
        { value => 'string',  label => 'String' },
        { value => 'int',     label => 'Integer' },
        { value => 'enum',    label => 'Enum' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Preference data type.']
    },
);

has_field 'enum' => (
    type => 'Repeatable',
    required => 0,
    setup_for_js => 1,
    num_when_empty => 0,
    do_wrapper => 1,
    do_label => 1,
    label => 'Enum values',
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An Array of enum.'],
    },
);

has_field 'enum.id' => (
    type => 'Hidden',
);

has_field 'enum.label' => (
    type => 'Text',
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'enum.value' => (
    type => 'Text',
    wrapper_class => [qw/hfh-rep-field/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Name will be prefixed with double underscore.']
    },
);

has_field 'enum.default_val' => (
    type => 'Boolean',
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'enum.rm' => (
    type => 'RmElement',
    value => 'Remove enum value description',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'enum_add' => (
    type => 'AddElement',
    repeatable => 'enum',
    value => 'Add enum value',
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
    render_list => [qw/id attribute fielddev_pref label max_occur description data_type enum enum_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_attribute {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    unless ($field->value =~ /^[a-z0-9_]+$/) {
        my $err_msg = 'Only lower-case, digits and _ allowed';
        $field->add_error($err_msg);
    }
    my $existing =  $c->model('DB')->resultset('voip_preferences')->search_rs({
        attribute => NGCP::Panel::Utils::Preferences::dynamic_pref_attribute_to_db($field->value) 
    })->first;

    #TODO: make it common, but what package to use?
    my $edit_id = -1;
    if (uc($c->req->method) eq 'PUT' || uc($c->req->method) eq 'PATCH') {
        $edit_id = $c->req->args->[0];
    } elsif($self->form->field('id')) {
        $edit_id = $self->form->field('id')->value
    }
    #/TODO

    if ( $existing && $existing->id != $edit_id ) {
        my $err_msg = 'This dynamic attribute already exists.';
        $field->add_error($err_msg);    
    }
}

sub validate_enum_value {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    unless($field->value =~ /^[a-z0-9_]+$/) {
        my $err_msg = 'Only lower-case, digits and _ allowed';
        $field->add_error($err_msg);
    }
}
1;
# vim: set tabstop=4 expandtab:
