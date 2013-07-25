package NGCP::Panel::Form::DestinationSet;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
);

has_field 'destination' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'destination.id' => (
    type => 'Hidden',
);

# dummy fields to provide accessors for our manually created ones
# in &set_destination_groups below
has_field 'destination.uri_destination' => (
    type => 'Hidden',
    value => undef,
);
has_field 'destination.uri_timeout' => (
    type => 'Hidden',
    value => undef,
);

has_field 'destination.destination' => (
    type => 'Select',
    widget => 'RadioGroup',
    label => 'Destination',
    do_label => 1,
    options_method => \&set_destination_groups,
    tags => {
        before_element => '<div class="ngcp-destination-row">',
        after_element => '</div>',
    },
);

sub set_destination_groups {
    my($self) = @_;
    my @options = ();

    my $parent_id = $self->parent->name;
    my $uri_d = "";
    my $uri_t = 300;
    if($parent_id =~ /^\d+$/ && 
       defined $self->form->ctx && 
       defined $self->form->ctx->stash->{cf_tmp_params}) {
        my $d = $self->form->ctx->stash->{cf_tmp_params}->{destination}->[$parent_id];
        $uri_d = $d->{uri_destination} if defined($d);
        $uri_t = $d->{uri_timeout} if defined($d);
    }

    push @options, { label => 'Voicemail', value => 'voicebox' };
    push @options, { label => 'Conference', value => 'conference' };
    push @options, { label => 'Fax2Mail', value => 'fax2mail' };
    push @options, { label => 'Calling Card', value => 'callingcard' };
    push @options, { label => 'Call Trough', value => 'callthrough' };
    push @options, { label => 'Local Subscriber', value => 'localuser' };
    push @options, { 
        label => 'URI/Number <input type="text" class="ngcp-destination-field" name="destination.'.$self->parent->name.'.uri_destination" value="'.$uri_d.'"/>'.
                 '<span> for </span>'.
                 '<input type="text" class="ngcp-destination-field" name="destination.'.$self->parent->name.'.uri_timeout" value="'.$uri_t.'"/>'.
                 '<span> seconds</span>',
        value => 'uri',
        selected => 1,
    };

    return \@options;
}

has_field 'destination.priority' => (
    type => 'PosInteger',
    label => 'Priority',
    wrapper_class => [qw/hfh-rep-field/],
    default => 1,
    required => 1,
);

has_field 'destination.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);


has_field 'destination_add' => (
    type => 'AddElement',
    repeatable => 'destination',
    value => 'Add another destination',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(name destination destination_add)],
);

has_field 'save' => (
    type => 'Submit',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    render_list => [qw(save)],
);

#sub validate_destination {
#    my ($self, $field) = @_;
#
#    # TODO: proper SIP URI check!
#    if($field->value !~ /^sip:.+\@.+$/) {
#        my $err_msg = 'Destination must be a valid SIP URI in format "sip:user@domain"';
#        $field->add_error($err_msg);
#    }
#}

1;

# vim: set tabstop=4 expandtab:
