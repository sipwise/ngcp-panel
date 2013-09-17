package NGCP::Panel::Form::DestinationSet;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
use NGCP::Panel::Field::PosInteger;
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

has_field 'destination.destination' => (
    type => 'Select',
    widget => 'RadioGroup',
    label => 'Destination',
    do_label => 1,
    options_method => \&build_destinations,
    default => 'uri',
    tags => {
        before_element => '<div class="ngcp-destination-row">',
        after_element => '</div>',
    },
);

sub build_destinations {
    my ($self) = @_;

    my @options = ();
    push @options, { label => 'Voicemail', value => 'voicebox' };
    my $c = $self->form->ctx;
    if(defined $c) {
        push @options, { label => 'Conference', value => 'conference' }
            if($c->config->{features}->{conference});
        push @options, { label => 'Fax2Mail', value => 'fax2mail' }
            if($c->config->{features}->{faxserver});
        push @options, { label => 'Calling Card', value => 'callingcard' }
            if($c->config->{features}->{callingcard});
        push @options, { label => 'Call Trough', value => 'callthrough' }
            if($c->config->{features}->{callthrough});
        push @options, { label => 'Local Subscriber', value => 'localuser' }
            if($c->config->{features}->{callthrough} || $c->config->{features}->{callingcard} );
    }
    push @options, { label => 'URI/Number', value => 'uri' };

    return \@options;
}

has_field 'destination.uri' => (
    type => 'Compound',
    do_label => 0,
);
has_field 'destination.uri.destination' => (
    type => 'Text',
    label => 'URI/Number',
    wrapper_class => [qw/hfh-rep-field/],
);
has_field 'destination.uri.timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    label => 'for (seconds)',
    default => 300,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.priority' => (
    type => '+NGCP::Panel::Field::PosInteger',
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
