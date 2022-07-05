package NGCP::Panel::Form::SubscriberProfile::Profile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

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
    required => 1,
    #not_nullable => 1, in the future?
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the Subscriber Profile.'],
    },
);

has_field 'set_default' => (
    type => 'Boolean',
    label => 'Default Profile',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Make this profile automatically the default profile for new subscribers having assigned the Profile Set this profile belongs.'],
    },
);

has_field 'attribute' => (
    type => 'Compound',
    label => 'Attributes',
    #do_label => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of subscriber preference names the subscriber can control.'],
    },
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
    render_list => [qw/name description set_default attribute/],
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
        -or => [
        {
            usr_pref => 1,
            expose_to_customer => 1,
        },
        {
            attribute => { -in => [qw/cfu cft cfna cfb cfs cfr cfo/] },
        }
        ],
    });
    
    my $fields = [];
    foreach my $pref($pref_rs->all) {
        my $desc = $pref->description;
        push @{ $fields }, 'attribute.'.$pref->attribute => {
            name => $pref->attribute,
            type => 'Checkbox',
            label => $pref->attribute,
            checkbox_value => $pref->id,
            element_attr => {
            #    rel => ['tooltip'],
            #    title => [$pref->description],
            #    checked => 'checked',
            },
            disabled => $c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit} ? 1 : 0,
        };
    }

    return $fields;
}

1;

# vim: set tabstop=4 expandtab:
