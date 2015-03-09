package NGCP::Panel::Form::Customer::PbxFieldDeviceExtensions;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

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
    label => '',
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

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/extension/],
);

1;
# vim: set tabstop=4 expandtab:
