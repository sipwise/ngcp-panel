package NGCP::Panel::Form::ProvisioningTemplate::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Utils::ProvisioningTemplates qw();
use NGCP::Panel::Utils::Generic qw(trim);

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

has_field 'scripting_lang' => (
    type => 'Select',
    label => 'Language',
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
  - name: first_name
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
  identifier: "firstname, lastname, status"
  reseller: default
  firstname_code: "function() { return row.first_name; }"
  lastname_code: "function() { return row.last_name; }"
  status: "active"
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
    render_list => [qw/name description scripting_lang yaml/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_yaml {

    my ($self, $field) = @_;

    eval {
        my $data = NGCP::Panel::Utils::ProvisioningTemplates::parse_template(undef, undef, undef, $field->value);
        NGCP::Panel::Utils::ProvisioningTemplates::validate_template($data);
    };
    if ($@) {
        $field->add_error(trim($@));
    }

}

sub validate {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless $c;

    my $field = $self->field('name');
    my $resource = Storable::dclone($self->values);
    if (defined $resource->{reseller}) {
        $resource->{reseller_id} = $resource->{reseller}{id};
        delete $resource->{reseller};
    } else {
        $resource->{reseller_id} = ($c->user->is_superuser ? undef : $c->user->reseller_id);
    }
    my $reseller;
    $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id}) if $resource->{reseller_id};

    eval {
        NGCP::Panel::Utils::ProvisioningTemplates::validate_template_name($c,
            $field->value,$c->stash->{old_name},$reseller);
    };
    if ($@) {
        $field->add_error(trim($@));
    }

}

1;
