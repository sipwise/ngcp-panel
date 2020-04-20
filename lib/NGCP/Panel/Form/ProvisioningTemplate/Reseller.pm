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
    label => 'Calculated fields',
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
    label => 'Template',
    cols => 200,
    rows => 100,
    maxlength => '67108864',
    #form_element_class => [],
    element_class => [qw/ngcp-provtemplate-area/],
    default => <<'EOS_DEFAULT_YAML',
fields:
  - name: fields
    label: "First Name:"
    type: Text
    required: 1
  - name: last_name
    label: "Last Name:"
    type: Text
    required: 1
  - name: cc
    label: "Country Code:"
    type: Text
    required: 1
  - name: ac
    label: "Area Code:"
    type: Text
    required: 1
  - name: sn
    label: "Subscriber Number:"
    type: Text
    required: 1
  - name: sip_username
    type: calculated
    value_code: "function() { return row.cc.concat(row.ac).concat(row.sn); }"
  - name: purge
    label: "Terminate subscriber, if exists:"
    type: Boolean
contract_contact:
  identifier: "firstname, lastname"
  reseller: default
  firstname_code: "function() { return row.first_name; }"
  lastname_code: "function() { return row.last_name; }"
contract:
  product: "Basic SIP Account"
  billing_profile: "Default Billing Profile"
  identifier: contact_id
  contact_id_code: "function() { return contract_contact.id; }"
subscriber:
  domain: "example.org"
  primary_number:
    cc_code: "function() { return row.cc; }"
    ac_code: "function() { return row.ac; }"
    sn_code: "function() { return row.sn; }"
  username_code: "function() { return row.sip_username; }"
  password_code: "function() { return row.sip_password; }"
subscriber_preferences:
  gpp0: "provisioning templates test"
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
        my $data = YAML::XS::Load($field->value);
        die('not a hash') unless 'HASH' eq ref $data;
        foreach my $section (qw/contract subscriber/) {
            die("section '$section' required") unless exists $data->{$section};
            die("section '$section' is not a hash") unless 'HASH' eq ref $data->{$section};
        }
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
