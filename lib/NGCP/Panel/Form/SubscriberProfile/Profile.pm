package NGCP::Panel::Form::SubscriberProfile::Profile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the Subscriber Profile.'],
    },
);

has_field 'description' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'catalog_default' => (
    type => 'Boolean',
    label => 'Default Profile',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Make this profile automatically the default profile for new subscribers having this profile catalog.'],
    },
);

has_field 'attribute' => (
    type => 'Compound',
    label => 'Attributes',
    #do_label => 1,
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
    render_list => [qw/name description catalog_default attribute/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub field_list {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    my $pref_rs = $c->model('DB')->resultset('voip_preferences')->search({
        usr_pref => 1,
        expose_to_customer => 1,
    });
    
    my $fields = [];
    foreach my $pref($pref_rs->all) {
        my $desc = $pref->description;
        push @{ $fields }, 'attribute.'.$pref->attribute => {
            type => 'Checkbox',
            label => $pref->attribute,
            checkbox_value => $pref->id,
            element_attr => {
            #    rel => ['tooltip'],
            #    title => [$pref->description],
            #    checked => 'checked',
            },
        };
    }

    return $fields;
}

sub field_names {
    my $self = shift;

    my %list = @{ $self->field_list };
    return [ sort keys %list ];
}

sub create_structure {
    my $self = shift;
    my $field_list = shift;
    
    my $list = $self->block('fields')->render_list;
    $self->block('fields')->render_list([ @{ $list }, @{ $field_list } ]);
}

1;

# vim: set tabstop=4 expandtab:
