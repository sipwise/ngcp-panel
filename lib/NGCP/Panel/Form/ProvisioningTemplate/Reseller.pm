package NGCP::Panel::Form::ProvisioningTemplate::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

use Storable qw();

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['A unique template name.']
    },
);

has_field 'description' => (
    type => 'Text',
    label => 'Description',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'lang' => (
    type => 'Select',
    options => [
        { value => 'js', label => 'JavaScript' },
        { value => 'perl', label => 'Perl' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Which scripting language used in the template.']
    },
);

has_field 'yaml' => (
    type => 'TextArea',
    required => 1,
    label => 'Body Template',
    cols => 200,
    rows => 10,
    maxlength => '67108864', # 64MB
    element_class => [qw/ngcp-autoconf-area/],
    default => <<'EOS_DEFAULT_YAML',
Dear Customer,

A new subscriber [% subscriber %] has been created for you.

Please go to [% url %] to set your password and log into your self-care interface.

Your faithful Sipwise system

--
This is an automatically generated message. Do not reply.
EOS_DEFAULT_YAML
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
    render_list => [qw/name description lang yaml/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_yaml {

    my ($self, $field) = @_;

    eval {
        die('no hash') unless 'HASH' eq ref YAML::XS::Load($field->value);
    };
    if ($@) {
        $field->add_error($@);
    }

}

sub validate_name {
    my ($self, $field) = @_;
    
    my $c = $self->ctx;
    return unless $c;

    if (not defined $c->stash->{old_name}
        or $c->stash->{old_name} ne $field->value) {
        $field->add_error("a provisioning template with name '" . $field->value . "' already exists")
            if exists $c->stash->{provisioning_templates}->{$field->value};
    }

}

1;
