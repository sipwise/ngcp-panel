package NGCP::Panel::Form::Customer::PbxFieldDevice;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'profile_id' => (
    type => 'Select',
    required => 1,
    label => 'Device Profile',
    options_method => \&build_profiles,
);
sub build_profiles {
    my ($self) = @_;
    my $c = $self->form->ctx;
    my $profile_rs = $c->stash->{autoprov_profile_rs};
    my @options = ();
    foreach my $p($profile_rs->all) {
        push @options, { label => $p->name, value => $p->id };
    }
    return \@options;
}

has_field 'identifier' => (
    type => 'Text',
    required => 1,
    label => 'MAC Address / Identifier',
);

has_field 'subscriber_id' => (
    type => 'Select',
    required => 1,
    label => 'Subscriber',
    options_method => \&build_subscribers,
);
sub build_subscribers {
    my ($self) = @_;
    my $c = $self->form->ctx;
    my $sub_rs = $c->stash->{contract}->voip_subscribers;
    my @options = ();
    foreach my $s($sub_rs->all) {
        push @options, { 
            label => $s->username . '@' . $s->domain->domain, 
            value => $s->provisioning_voip_subscriber->id 
        };
    }
    return \@options;
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/profile_id identifier subscriber_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
