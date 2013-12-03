package NGCP::Panel::Controller::API::Root;
use Sipwise::Base;
use namespace::sweep;
use Data::Record qw();
use DateTime::Format::HTTP qw();
use Digest::SHA3 qw(sha3_256_base64);
use Encode qw(encode);
use HTTP::Headers qw();
use HTTP::Response qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use Regexp::Common qw(delimited); # $RE{delimited}{-delim=>'"'}
use File::Find::Rule;
BEGIN { extends 'Catalyst::Controller'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';

class_has('dispatch_path', is => 'ro', default => '/api/');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => [qw(API::Root invalid_user)],
            AllowedRole => 'api_admin',
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub GET : Allow {
    my ($self, $c) = @_;
    my $response = $self->cached($c);
    unless ($response) {
        $c->stash(template => 'api/root.tt');
        $c->forward($c->view);
        $c->response->headers(HTTP::Headers->new(
            Cache_Control => 'no-cache, public',
            Content_Language => 'en',
            Content_Type => 'application/xhtml+xml',
            ETag => $self->etag($c->response->body),
            Expires => DateTime::Format::HTTP->format_datetime($self->expires),
            Last_Modified => DateTime::Format::HTTP->format_datetime($self->last_modified),
            $self->collections_link_headers,
        ));
        $c->cache->set($c->request->uri->canonical->as_string, $response, { expires_at => $self->expires->epoch });
    }
    return;
}

sub HEAD : Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS : Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Content_Language => 'en',
        $self->collections_link_headers,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub collections_link_headers : Private {
    my ($self) = @_;

    # figure out base path of our api modules
    my $libpath = $INC{"NGCP/Panel/Controller/API/Root.pm"};
    $libpath =~ s/Root\.pm$//;

    # find all modules not called Root.pm and *Item.pm
    # (which should then be just collections)
    my $rootrule = File::Find::Rule->new->name('Root.pm');
    my $itemrule = File::Find::Rule->new->name('*Item.pm');
    my $rule = File::Find::Rule->new
        ->mindepth(1)
        ->maxdepth(1)
        ->name('*.pm')
        ->not($rootrule)
        ->not($itemrule);
    my @colls = $rule->in($libpath);

    # create Link header for each of the collections
    my @links = ();
    foreach my $mod(@colls) {
        # extract file base from path (e.g. Foo from lib/something/Foo.pm)
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        my $rel = lc $mod;
        $mod = 'NGCP::Panel::Controller::API::'.$mod;
        my $dp = $mod->dispatch_path;
        push @links, Link => '<'.$dp.'>; rel="collection http://purl.org/sipwise/ngcp-api/#rel-'.$rel.'"';
    }
    return @links;
}

sub invalid_user : Private {
    my ($self, $c, $ssl_client_m_serial) = @_;
    $self->error($c, HTTP_FORBIDDEN, "Invalid certificate serial number '$ssl_client_m_serial'.");
    return;
}

sub last_modified : Private {
    my ($self, $octets) = @_;
    return DateTime->new(year => 2013, month => 11, day => 11); # XXX insert release timestamp
}

sub end : Private {
    my ($self, $c) = @_;
    
    #$c->log->debug("++++++++++++++++ response body: " . $c->response->body // '');
}

# vim: set tabstop=4 expandtab:
