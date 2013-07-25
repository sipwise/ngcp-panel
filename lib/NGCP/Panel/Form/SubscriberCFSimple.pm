package NGCP::Panel::Form::SubscriberCFSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'destination' => (
    type => 'Compound', 
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
        before_element => '<div class="ngcp-destination-row-simple">',
        after_element => '</div>',
    },
);

sub set_destination_groups {
    my($self) = @_;
    my @options = ();

    my $uri_d = "";
    my $uri_t = 300;
    if(defined $self->form->ctx && 
       defined $self->form->ctx->stash->{cf_tmp_params}) {
        my $d = $self->form->ctx->stash->{cf_tmp_params};
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
        label => 'URI/Number <input type="text" class="ngcp-destination-field" name="destination.uri_destination" value="'.$uri_d.'"/>'.
                 '<span> for </span>'.
                 '<input type="text" class="ngcp-destination-field" name="destination.uri_timeout" value="'.$uri_t.'"/>'.
                 '<span> seconds</span>',
        value => 'uri',
        selected => 1,
    };

    return \@options;
}

has_field 'cf_actions' => (
    type => 'Compound',
    do_label => 0,
    do_wrapper => 1,
    wrapper_class => [qw(row pull-right)],
);

has_field 'cf_actions.save' => (
    type => 'Button',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
    wrapper_class => [qw(pull-right)],
);

has_field 'cf_actions.advanced' => (
    type => 'Button', 
    do_label => 0,
    value => 'Advanced View',
    element_class => [qw(btn btn-tertiary)],
    wrapper_class => [qw(pull-right)],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(submitid destination)],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(cf_actions)],);

1;

# vim: set tabstop=4 expandtab:
