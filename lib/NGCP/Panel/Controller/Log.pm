package NGCP::Panel::Controller::Log;
use Sipwise::Base;

BEGIN { use parent 'Catalyst::Controller'; }

use LWP::UserAgent;
my $ua = LWP::UserAgent->new;
$ua->timeout(3);

# a proxy for kibana/elasticsearch

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :Chained('/') :PathPart('log') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub static :Chained('root') :PathPart('') :Args() {
    my ($self, $c, @fullpath) = @_;
    my $path = join '/', @fullpath;
    $path ||= 'index.html';
    $path = 'kibana/'.$path;

    $c->stash(template => $path);
    $c->forward($c->view('TT'));

    if($path eq "kibana/config.js") {
        my $defp = '/dashboard/file/NGCP-Summary.json';
        my $eurl = $c->uri_for_action('/log/elastic')->as_string;
        my $body = $c->res->body;
        $body =~ s/(\s*elasticsearch:\s*)"[^,]+"/$1"$eurl"/g;
        $body =~ s/(\s*default_route\s*:\s*)'[^,]+'/$1'$defp'/g;
        $c->res->body($body);
    }
}

sub elastic :Chained('root') :PathPart('ngcpelastic') :Args() {
    my ($self, $c, @fullpath) = @_;
    my $path = join '/', @fullpath;
    $path .= '?' . $c->req->uri->query if $c->req->uri->query;

    my $req = HTTP::Request->new($c->req->method => 'http://' . $c->config->{elasticsearch}->{host} . ':' . $c->config->{elasticsearch}->{port} . '/'.$path);
    $req->header('Content-Type' => $c->req->header('Content-Type'));
    my $body = $c->request->body ? (do { local $/; $c->request->body->getline }) : '';
    $req->content($body);
    my $res = $ua->request($req);
    $c->res->content_type($res->header('Content-Type') // 'text/plain');
    $c->res->status($res->code);
    $c->res->body($res->decoded_content);
}


__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
