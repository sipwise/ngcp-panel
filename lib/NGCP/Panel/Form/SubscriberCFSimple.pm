package NGCP::Panel::Form::SubscriberCFSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
use NGCP::Panel::Field::PosInteger;
use NGCP::Panel::Field::URI;
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

has_field 'destination.destination' => (
    type => 'Select',
    widget => 'RadioGroup',
    label => 'Destination',
    do_label => 1,
    options_method => \&build_destinations,
    default => 'uri',
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
        push @options, { label => 'Call Through', value => 'callthrough' }
            if($c->config->{features}->{callthrough});
        push @options, { label => 'Auto Attendant', value => 'autoattendant' }
            if($c->config->{features}->{cloudpbx} && $c->stash->{pbx});
        push @options, { label => 'Office Hours Announcement', value => 'officehours' }
            if($c->config->{features}->{cloudpbx} && $c->stash->{pbx});
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
    type => '+NGCP::Panel::Field::URI',
    label => 'URI/Number',
);
has_field 'destination.uri.timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    label => 'for (seconds)',
    default => 300,
);

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
    render_list => [qw(destination)],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(cf_actions)],);

1;

# vim: set tabstop=4 expandtab:
