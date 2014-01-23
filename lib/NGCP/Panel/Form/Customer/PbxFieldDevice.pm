package NGCP::Panel::Form::Customer::PbxFieldDevice;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'profile_id' => (
    type => 'Select',
    required => 1,
    label => 'Device Profile',
    options_method => \&build_profiles,
);
sub build_profiles {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return unless $c;
    my $profile_rs = $c->stash->{autoprov_profile_rs};
    my @options = ();
    push @options, { label => '', value => undef };
    foreach my $p($profile_rs->all) {
        push @options, { label => $p->name, value => $p->id };
    }
    return \@options;
}

has_field 'identifier' => (
    type => 'Text',
    required => 1,
    label => 'MAC Address / Identifier',
);

has_field 'station_name' => (
    type => 'Text',
    required => 1,
    label => 'Station Name',
);

has_field 'line' => (
    type => 'Repeatable',
    label => 'Lines/Keys',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
);

has_field 'line.id' => (
    type => 'Hidden',
);

has_field 'line.subscriber_id' => (
    type => 'Select',
    required => 1,
    label => 'Subscriber',
    options_method => \&build_subscribers,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber to use on this line/key'],
    },
);
sub build_subscribers {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return unless $c;
    my $sub_rs = $c->stash->{contract}->voip_subscribers;
    my @options = ();
    foreach my $s($sub_rs->all) {
        next unless($s->status eq 'active');
        push @options, { 
            label => $s->username . '@' . $s->domain->domain, 
            value => $s->provisioning_voip_subscriber->id 
        };
    }
    return \@options;
}


has_field 'line.line' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key',
    options => [],
    no_option_validation => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The line/key to use'],
    },
    element_class => [qw/ngcp-linekey-select/],
);
sub validate_line_line {
    my ($self, $field) = @_;
    $field->clear_errors;
    unless($field->value =~ /^\d+\.\d+\.\d+$/) {
        my $err_msg = 'Invalid line value';
        $field->add_error($err_msg);
    }
    return;
}

has_field 'line.type' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key Type',
    options => [],
    no_option_validation => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The type of feature to use on this line/key'],
    },
    element_class => [qw/ngcp-linetype-select/],
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

has_field 'line.rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'line_add' => (
    type => 'AddElement',
    repeatable => 'line',
    value => 'Add another Line/Key',
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
    render_list => [qw/profile_id identifier station_name line line_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
