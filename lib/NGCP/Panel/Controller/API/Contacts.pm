package NGCP::Panel::Controller::API::Contacts;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use Data::Record qw();
use DateTime::Format::HTTP qw();
use DateTime::Format::RFC3339 qw();
use Digest::SHA3 qw(sha3_256_base64);
use HTTP::Headers qw();
use HTTP::Headers::Util qw(split_header_words);
use HTTP::Status qw(:constants);
#use JE qw();
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Form::Contact::Admin qw();
use NGCP::Panel::Form::Contact::Reseller qw();
use NGCP::Panel::ValidateJSON qw();
use Path::Tiny qw(path);
use Regexp::Common qw(delimited); # $RE{delimited}
use Safe::Isa qw($_isa);
use Types::Standard qw(InstanceOf);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::QueryParameter;
require Catalyst::ActionRole::RequireSSL;
require URI::QueryParam;

with 'NGCP::Panel::Role::API';

class_has('dispatch_path', is => 'ro', default => '/api/contacts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-contacts');
has('last_modified', is => 'rw', isa => InstanceOf['DateTime']);

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'api_admin',
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
            QueryParam => '!id',
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods QueryParameter)],
);

sub GET : Allow {
    my ($self, $c) = @_;
    {
        last if $self->cached($c);
        my $contacts = $c->model('DB')->resultset('contacts');
        $self->last_modified($contacts->get_column('modify_timestamp')->max_rs->single->modify_timestamp);
        my (@embedded, @links);
        for my $contact ($contacts->search({}, {order_by => {-asc => 'me.id'}, prefetch => ['reseller']})->all) {
            push @embedded, $self->hal_from_contact($contact);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:contacts',
                href     => sprintf('/api/contacts/?id=%d', $contact->id),
            );
        }
        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [
                Data::HAL::Link->new(
                    relation => 'curies',
                    href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                    name => 'ngcp',
                    templated => true,
                ),
                Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
                Data::HAL::Link->new(relation => 'self', href => '/api/contacts/'),
                @links,
            ]
        );
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-contacts)"|rel="item $1"|;
                s/rel=self/rel="collection self"/;
                $_
            } $hal->http_headers),
            Cache_Control => 'no-cache, private',
            ETag => $self->etag($hal->as_json),
            Expires => DateTime::Format::HTTP->format_datetime($self->expires),
            Last_Modified => DateTime::Format::HTTP->format_datetime($self->last_modified),
        ), $hal->as_json);
        $c->cache->set($c->request->uri->canonical->as_string, $response, { expires_at => $self->expires->epoch });
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
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
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-contacts',
        Content_Language => 'en',
    ));
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/allowed_methods.tt', allowed_methods => $allowed_methods);
    return;
}

sub POST : Allow {
    my ($self, $c) = @_;

    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $contact_form;
        if($c->user->roles eq "api_admin") {
            $contact_form = NGCP::Panel::Form::Contact::Admin->new;
        } else {
            $contact_form = NGCP::Panel::Form::Contact::Reseller->new;
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $contact_form,
        );

        my $now = DateTime->now;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $contact;
        try {
            $contact = $c->model('DB')->resultset('contacts')->create($resource);
        } catch($e) {
            $c->log->error("failed to create contact: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "failed to create contact");
            last;
        }

        $c->cache->remove($c->request->uri->canonical->as_string);
        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/api/contacts/?id=%d', $contact->id));
        $c->response->body(q());
    }
    return;
}

sub allowed_methods : Private {
    my ($self) = @_;
    my $meta = $self->meta;
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
    unless ($response) {
        $c->log->info('not cached');
        return;
    }
    my $matched_tag = $c->request->header('If-None-Match') && ('*' eq $c->request->header('If-None-Match'))
      || (grep {$response->header('ETag') eq $_} Data::Record->new({
        split => qr/\s*,\s*/, unless => $RE{delimited}{-delim => q(")},
      })->records($c->request->header('If-None-Match')));
    my $not_modified = $c->request->header('If-Modified-Since')
        && !($self->last_modified < DateTime::Format::HTTP->parse_datetime($c->request->header('If-Modified-Since')));
    if (
        $matched_tag && $not_modified
        || $matched_tag
        || $not_modified
    ) {
        $c->response->status(HTTP_NOT_MODIFIED);
        $c->response->headers($response->headers);
        $c->log->info('cached');
        return 1;
    }
    $c->log->info('stale');
    return;
}

sub etag : Private {
    my ($self, $octets) = @_;
    return sprintf '"ni:/sha3-256;%s"', sha3_256_base64($octets);
}

sub expires : Private {
    my ($self) = @_;
    return DateTime->now->clone->add(years => 1); # XXX insert product end-of-life
}

sub hal_from_contact : Private {
    my ($self, $contact) = @_;
    # XXX invalid 00-00-00 dates
    my %resource = $contact->get_inflated_columns;
    my $id = delete $resource{id};


    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => '/api/contacts/'),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => "/api/contacts/?id=$id"),
            $contact->reseller
                ? Data::HAL::Link->new(
                    relation => 'ngcp:resellers',
                    href => sprintf('/api/resellers/?id=%d', $contact->reseller_id),
                ) : (),
        ],
        relation => 'ngcp:contacts',
    );

    my %fields = map { $_->name => undef } grep { 'Text' eq $_->type || 'Email' eq $_->type }
        NGCP::Panel::Form::Contact::Reseller->new->fields;
    for my $k (keys %resource) {
        delete $resource{$k} unless exists $fields{$k};
        $resource{$k} = DateTime::Format::RFC3339->format_datetime($resource{$k}) if $resource{$k}->$_isa('DateTime');
    }
    $hal->resource({%resource});
    return $hal;
}

sub valid_id : Private {
    my ($self, $c, $id) = @_;
    return 1 if $id->is_integer;
    $c->response->status(HTTP_BAD_REQUEST);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/invalid_query_parameter.tt', key => 'id');
    return;
}

sub end : Private {
    my ($self, $c) = @_;
    $c->forward(qw(Controller::Root render));
    $c->response->content_type('')
        if $c->response->content_type =~ qr'text/html'; # stupid RenderView getting in the way
    if (@{ $c->error }) {
        my $msg = join ', ', @{ $c->error };
        $c->log->error($msg);
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        $c->clear_errors;
    }
}

# vim: set tabstop=4 expandtab:
