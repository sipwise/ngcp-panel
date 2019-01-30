package NGCP::Panel::Form::TimeSet::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

use NGCP::Panel::Utils::TimeSet;

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 0,
    label_attr => {
        rel => ['tooltip'],
        title => ['Name should be specified in the input field or in the uploaded calendar file. Name from the form input has priority.']
    },
);

has_field 'upload' => ( 
    type => 'Upload',
    max_size => '67108864', # 64MB
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
    render_list => [qw/id name upload/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my ($self, $field) = @_;
    my $c = $self->ctx;
    return unless $c;
    my $schema = $c->model('DB');

    my $reseller_id;
    #Todo: to some utils?
    if ($c->user->roles eq 'admin') {
        if ($self->field('reseller')) {
            $reseller_id = $self->field('reseller')->value;
        } elsif($c->stash->{reseller}) { #strange, reseller interface keeps rs as reseller, not reseller_rs
            $reseller_id = $c->stash->{reseller}->first->id;
        }
    } else {
        $reseller_id = $c->user->reseller_id
    }
    unless ($reseller_id) {
        #we shouldn't get here
        $self->field('name')->add_error($c->loc('Unknow reseller'));
    }
    #/todo

    my $name = $self->field('name')->value;

    my $timeset_uploaded = {};
    if ($self->field('upload')->value) {
        ($timeset_uploaded) = NGCP::Panel::Utils::TimeSet::parse_calendar( c => $c );
    }
    if (!$name) {
        if (!$timeset_uploaded->{name}) {
            $self->field('name')->add_error($c->loc('Name field is required and should be defined in the form field or in the uploaded calendar file.'));
        } else {
            $name = $timeset_uploaded->{name};
        }
    }
    my $existing_item = $schema->resultset('voip_time_sets')->find({
        name => $name,
    });
    my $current_item = $self->item ? $self->item : $c->stash->{timeset_rs};
    if ($existing_item && (!$current_item || $existing_item->id != $current_item->id)) {
        $self->field('name')->add_error($c->loc('This name already exists'));
    }
}
1;

# vim: set tabstop=4 expandtab:
