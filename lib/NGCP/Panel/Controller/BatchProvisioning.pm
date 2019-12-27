package NGCP::Panel::Controller::BatchProvisioning;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

#use NGCP::Panel::Form;

#use NGCP::Panel::Utils::Contract;
#use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
#use NGCP::Panel::Utils::DateTime;
#use NGCP::Panel::Utils::Billing;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    $c->config->{features}->{batch_provisioning} = 1;
    $c->detach('/denied_page')
        unless($c->config->{features}->{batch_provisioning});
    return 1;
}

sub template_list :Chained('/') :PathPart('batchprovisioning') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{template_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "type", search => 1, title => $c->loc('Type') },
        { name => "description", search => 1, title => $c->loc('Description') },
    ]);

    $c->stash(template => 'batchprovisioning/list.tt');
}

sub root :Chained('template_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('template_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $templates = [ { type => "xy", description => "blah" } ];

    NGCP::Panel::Utils::Datatables::process_static_data($c, $templates, $c->stash->{template_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

1;

