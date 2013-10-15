package NGCP::Panel::Controller::API::Root;
use Sipwise::Base;
use namespace::sweep;
use Data::Record qw();
use DateTime::Format::HTTP qw();
use Digest::SHA3 qw(sha3_256_base64);
use Encode qw(encode);
use HTTP::Headers qw();
use HTTP::Response qw();
use HTTP::Status qw(HTTP_NOT_MODIFIED HTTP_OK);
use MooseX::ClassAttribute qw(class_has);
use Regexp::Common qw(delimited); # $RE{delimited}{-delim=>'"'}
BEGIN { extends 'Catalyst::Controller'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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
    my $allowed_methods = $self->allowed_methods->join(q(, ));
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods,
        Content_Language => 'en',
        $self->collections_link_headers,
    ));
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/allowed_methods.tt', allowed_methods => $allowed_methods);
    return;
}

sub allowed_methods : Private {
    my $meta = __PACKAGE__->meta;
    my @allow;
    for my $method ($meta->get_method_list) {
        push @allow, $meta->get_method($method)->name
            if $meta->get_method($method)->can('attributes') && 'Allow' ~~ $meta->get_method($method)->attributes;
    }
    return [sort @allow];
}

sub cached : Private {
    my ($self, $c) = @_;
    my $response = $c->cache->get($c->request->uri->canonical->as_string);
    return unless $response;
    my $matched_tag = $c->request->header('If-None-Match')
        && ('*' eq $c->request->header('If-None-Match'))
        || (
            grep { $response->header('ETag') eq $_ }
            Data::Record->new({ split => qr/\s*,\s*/, unless => $RE{quoted}, })
                ->records($c->request->header('If-None-Match'))
        );
    my $not_modified = $c->request->header('If-Modified-Since')
        && !($self->last_modified < DateTime::Format::HTTP->parse_datetime($c->request->header('If-Modified-Since')));
    if (
        $matched_tag && $not_modified
        || $matched_tag
        || $not_modified
    ) {
        $response->code(HTTP_NOT_MODIFIED);
        $response->content(undef);
        return $response;
    }
    return;
}

sub collections_link_headers : Private {
    my ($self) = @_;
    return (
        # XXX introspect class attribute API/*.pm->dispatch_path
        Link => '</api/contacts/>; rel="collection http://purl.org/sipwise/ngcp-api/#rel-contacts"',
        Link => '</api/contracts/>; rel="collection http://purl.org/sipwise/ngcp-api/#rel-contracts"',
        # Link => '</api/resellers/>; rel=collection', # XXX does not exist yet
    );
}

sub etag : Private {
    my ($self, $octets) = @_;
    return sprintf '"ni:/sha3-256;%s"', sha3_256_base64($octets);
}

sub expires : Private {
    my ($self) = @_;
    return DateTime->now->clone->add(years => 1); # XXX insert install timestamp + 1000 days/ product end-of-life
}

sub invalid_user : Private {
    my ($self, $c, $ssl_client_m_serial) = @_;
    $c->response->status(403);
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/invalid_user.tt', ssl_client_m_serial => $ssl_client_m_serial);
    return;
}

sub last_modified : Private {
    my ($self, $octets) = @_;
    return DateTime->new(year => 2013, month => 11, day => 11); # XXX insert release timestamp
}
