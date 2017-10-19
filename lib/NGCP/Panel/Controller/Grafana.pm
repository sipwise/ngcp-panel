package NGCP::Panel::Controller::Grafana;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use LWP::UserAgent;
my $ua = LWP::UserAgent->new(max_redirect => 0);
$ua->timeout(3);

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :Chained('/') :PathPart('grafana') :Args() {
    my ( $self, $c, @fullpath ) = @_;

    my $grafana_user;
    my $admin = $c->req->param('ngcp_grafana_admin') // $c->session->{ngcp_grafana_admin} // 'no';
    if($admin eq "yes") {
        $grafana_user = 'admin';
        $c->session->{ngcp_grafana_admin} = 'yes';
    } else {
        $grafana_user = $c->user->login;
        delete $c->session->{ngcp_grafana_admin};
    }

    my $path = join '/', @fullpath;
    $path .= '?' . $c->req->uri->query if $c->req->uri->query;
    my $url = $c->config->{grafana}{schema} . '://' .
              $c->config->{grafana}{host} . ':' .
              $c->config->{grafana}{port};
    $url .= "/".$path if length $path;

    my $req = HTTP::Request->new($c->req->method => $url);
    $req->header('Content-Type' => $c->req->header('Content-Type'));
    $req->header('X-WEBAUTH-USER' => $grafana_user);
    my $body = $c->request->body ? (do { local $/; $c->request->body->getline }) : '';
    $req->content($body);
    my $res = $ua->request($req);
    $c->res->content_type($res->header('Content-Type') // 'text/plain');
    if($res->header('Location')) {
        $c->res->header(Location => $res->header('Location'))
    }
    $c->res->status($res->code);
    $c->res->body($res->decoded_content);
}



1;

# vim: set tabstop=4 expandtab:
