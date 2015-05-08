package NGCP::Panel::Form::BillingNetwork::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use NGCP::Panel::Utils::BillingNetworks qw();
use Storable qw();

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Billing Network Name',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the billing network.']
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

has_field 'blocks' => (
    type => 'Repeatable',
    required => 1,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of billing network blocks, each containing the keys (base) "ip" address and an optional "mask" to specify the network portion (subnet prefix length).'],
    },
    validate_method => \&_validate_blocks,
    inflate_default_method => \&_inflate_blocks,
);

has_field 'blocks.row' => (
    type => 'Compound',
    label => 'Billing Network Block',
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-network-block-row">',
        after_element => '</div>',
    },
);

has_field 'blocks.row.ip' => (
    type => '+NGCP::Panel::Field::IPAddress',
    required => 1,
    element_attr => {
        rel => ['tooltip'], 
        title => ['(Base) IP Address'] 
    },
    do_label => 0,
    do_wrapper => 0,    
);

has_field 'blocks.row.mask' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 0,
    maxlength => 3,
    element_attr => {
        rel => ['tooltip'], 
        title => ['Optional Subnet Prefix Length'] 
    },
    do_label => 0,
    do_wrapper => 0,
    tags => {
        before_element => '&nbsp;/',
    },    
);

has_field 'blocks.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);


has_field 'blocks_add' => (
    type => 'AddElement',
    repeatable => 'blocks',
    value => 'Add another billing network block',
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
    render_list => [qw/id name description blocks blocks_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub _validate_blocks {
    my ($self,$field) = @_;
    my $blocks = Storable::dclone($field->value);
    foreach my $block (@$blocks) {
        $block->{ip} = $block->{row}->{ip};
        $block->{mask} = $block->{row}->{mask};
        delete $block->{row};
    }
    NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($blocks,sub {
        my ($err) = @_;
        $field->add_error($err); 
    });
    $field->value($blocks);
    return 1;
}

sub _inflate_blocks {
    my ($field,$value) = @_;
    my @blocks = ();
    foreach my $block (@$value) {
        my %row = ();
        $row{ip} = $block->{ip};
        $row{mask} = $block->{mask};
        push(@blocks,{ row => \%row });
    }
    return (scalar @blocks == 0 ? undef : \@blocks);
}

1;
# vim: set tabstop=4 expandtab: