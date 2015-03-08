package NGCP::Panel::Form::Customer::PbxFieldDevice;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'profile_id' => (
    type => 'Select',
    required => 1,
    label => 'Device',
    options_method => \&build_profiles,
    element_attr => {
        rel => ['tooltip'],
        title => ['The PBX device.']
    },
);
sub build_profiles {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return unless $c;
    my $profile_rs = $c->stash->{autoprov_profile_rs};
    my @options = ();
    foreach my $p($profile_rs->all) {
        push @options, { label => $p->name, value => $p->id };
    }
    return \@options;
}

has_field 'extension' => (
    type => 'Repeatable',
    required => 0,
    label => 'Device Extension',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Extensions available for the device model.'],
    },
);

has_field 'extension.id' => (
    type => 'Hidden',
);

has_field 'extension.extension_id' => (
    type => 'Select',
    label => 'Extension',
    default => '',
    required => 0,
    options_method => \&build_extensions,
    element_attr => {
        rel => ['tooltip'],
        title => ['Extension devices.'],
    },
);

has_field 'extension.rm' => (
    type => 'RmElement',
    value => 'Remove Extension',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'extension_add' => (
    type => 'AddElement',
    repeatable => 'keys',
    value => 'Add Extension',
    element_class => [qw/btn btn-primary pull-right/],
);

sub build_extensions {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return unless $c;
    my $model_extensions_rs = $c->stash->{model_extensions_rs};
    my @options = ();
    foreach my $e($model_extensions_rs->all) {
        push @options, { label => $e->device->vendor.' '.$e->device->model, value => $e->device->id };
    }
    return \@options;
}

has_field 'identifier' => (
    type => 'Text',
    required => 1,
    label => 'MAC Address',
    element_attr => {
        rel => ['tooltip'],
        title => ['The MAC address of the device.']
    },
);

has_field 'station_name' => (
    type => 'Text',
    required => 1,
    label => 'Station Name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The name to display on the device (usually the name of the person this device belongs to).']
    },
);

has_field 'line' => (
    type => 'Repeatable',
    label => 'Lines/Keys',
    do_wrapper => 0,
    do_label => 0,
);

has_field 'line.subscriber_id' => (
    type => 'Hidden',
    required => 1,
);

has_field 'line.line' => (
    type => 'Hidden',
    required => 1,
);
sub validate_line_line {
    my ($self, $field) = @_;
    $field->clear_errors;
    unless($field->value =~ /^\d+\.\d+$/) {
        my $err_msg = 'Invalid line value';
        $field->add_error($err_msg);
    }
    return;
}

has_field 'line.type' => (
    type => 'Hidden',
    required => 1,
);
sub validate_line_type {
    my ($self, $field) = @_;
    $field->clear_errors;
    unless($field->value eq 'private' ||
           $field->value eq 'shared' ||
           $field->value eq 'blf') {
        my $err_msg = 'Invalid line type, must be private, shared or blf';
        $field->add_error($err_msg);
    }
    return;
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
    render_list => [qw/profile_id identifier station_name line/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
