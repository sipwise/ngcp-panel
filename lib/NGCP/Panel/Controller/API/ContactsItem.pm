package NGCP::Panel::Controller::API::ContactsItem;
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
use HTTP::Status qw(:constants);
use JSON qw();
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Form::Contact::Reseller qw();
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';

class_has('dispatch_path', is => 'ro', default => '/api/contacts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-contacts');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'api_admin',
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        last if $self->cached($c);
        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, contact => $contact);
        my $hal = $self->hal_from_contact($contact);
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
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

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
        Content_Language => 'en',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $media_type = 'application/json-patch+json';
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        last unless $self->valid_id($c, $id);
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, $media_type);
        last unless $self->require_precondition($c, 'If-Match');
        my $preference = $self->require_preference($c);
        last unless $preference;
        my $cached = $c->cache->get($c->request->uri->canonical->as_string);
        my ($contact, $entity);
        if ($cached) {
            try {
                die 'not a response object' unless $cached->$_isa('HTTP::Response');
            } catch($e) {
                die "cache poisoned: $e";
            };
            last unless $self->valid_precondition($c, $cached->header('ETag'), 'contact');
            try {
                NGCP::Panel::Utils::ValidateJSON->new($cached->content);
                $entity = JSON::decode_json($cached->content);
            } catch($e) {
                die "cache poisoned: $e";
            };
        } else {
            if ('*' eq $c->request->header('If-Match')) {
                $contact = $self->contact_by_id($c, $id);
                last unless $self->resource_exists($c, contact => $contact);
                $entity = JSON::decode_json($self->hal_from_contact($contact)->as_json);
            } else {
	    	$self->error($c, HTTP_PRECONDITION_FAILED, "This 'contact' entity cannot be found, it is either expired or does not exist. Fetch a fresh one.");
                last;
            }
        }
        last unless $self->require_body($c);
        my $json = do { local $/; $c->request->body->getline }; # slurp
        last unless $self->require_wellformed_json($c, $media_type, $json);
        last unless $self->require_valid_patch($c, $json);
        $entity = $self->apply_patch($c, $entity, $json);
        last unless $entity;
        last unless $self->valid_entity($c, $entity);

        my $hal = Data::HAL->from_json(
            JSON::to_json($entity, { canonical => 1, convert_blessed => 1, pretty => 1, utf8 => 1 })
        );

        my $r_id;
        {
            my $reseller_link = ($hal->links // [])->grep(sub {
                $_->relation->eq('http://purl.org/sipwise/ngcp-api/#rel-resellers')
            });

            if ($reseller_link->size) {
                my $reseller_uri = URI->new_abs($reseller_link->at(0)->href->as_string, $c->req->uri)->canonical;
                my $resellers_uri = URI->new_abs('/api/resellers/', $c->req->uri)->canonical;
                if (0 != index $reseller_uri, $resellers_uri) {
                    $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
                    $c->response->header('Content-Language' => 'en');
                    $c->response->content_type('application/xhtml+xml');
                    $c->stash(
                        template => 'api/unprocessable_entity.tt',
                        error_message => "The link $reseller_uri cannot express a reseller relationship.",
                    );
                    last;
                }
                $r_id = $reseller_uri->rel($resellers_uri)->query_param('id');
                last unless $self->valid_id($c, $r_id);
            }
        }
        my $resource = $hal->resource;

        my $contact_form = NGCP::Panel::Form::Contact::Reseller->new;
        my %fields = map { $_->name => undef } grep { 'Text' eq $_->type || 'Email' eq $_->type } $contact_form->fields;
        for my $k (keys %{ $resource }) {
            delete $resource->{$k} unless exists $fields{$k};
            $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
                if $resource->{$k}->$_isa('DateTime');
        }
        my $result = $contact_form->run(params => $resource);
        if ($result->error_results->size) {
            $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
            $c->response->header('Content-Language' => 'en');
            $c->response->content_type('application/xhtml+xml');
            my $e = $result->error_results->map(sub {
                sprintf '%s: %s - %s', $_->name, $_->input, $_->errors->join(q())
            })->join("\n");
            $c->stash(
                template => 'api/unprocessable_entity.tt',
                error_message => "Validation failed: $e",
            );
            last;
        }

        $resource->{reseller_id} = $r_id;
        $resource->{modify_timestamp} = DateTime->now;
        $contact = $self->contact_by_id($c, $id) unless $contact;
        $contact->update($resource);
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->cache->remove($c->request->uri->canonical->as_string);
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            $hal = $self->hal_from_contact($contact);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
                Cache_Control => 'no-cache, private',
                ETag => $self->etag($hal->as_json),
                Expires => DateTime::Format::HTTP->format_datetime($self->expires),
                Last_Modified => DateTime::Format::HTTP->format_datetime($self->last_modified),
            ), $hal->as_json);
            $c->cache->set($c->request->uri->canonical->as_string, $response, { expires_at => $self->expires->epoch });
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation'); # don't cache this
            $c->response->body($response->content);
        }
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $media_type = 'application/hal+json';
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        last unless $self->valid_id($c, $id);
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, $media_type);
        last unless $self->require_precondition($c, 'If-Match');
        my $preference = $self->require_preference($c);
        last unless $preference;
        my $cached = $c->cache->get($c->request->uri->canonical->as_string);
        my ($contact, $entity);
        if ($cached) {
            try {
                die 'not a response object' unless $cached->$_isa('HTTP::Response');
            } catch($e) {
                die "cache poisoned: $e";
            };
            last unless $self->valid_precondition($c, $cached->header('ETag'), 'contact');
            try {
                NGCP::Panel::Utils::ValidateJSON->new($cached->content);
                $entity = JSON::decode_json($cached->content);
            } catch($e) {
                die "cache poisoned: $e";
            };
        } else {
            if ('*' eq $c->request->header('If-Match')) {
                $contact = $self->contact_by_id($c, $id);
                last unless $self->resource_exists($c, contact => $contact);
                $entity = JSON::decode_json($self->hal_from_contact($contact)->as_json);
            } else {
	    	$self->error($c, HTTP_PRECONDITION_FAILED, "This 'contact' entity cannot be found, it is either expired or does not exist. Fetch a fresh one.");
                last;
            }
        }
        last unless $self->require_body($c);
        my $json = do { local $/; $c->request->body->getline }; # slurp
        last unless $self->require_wellformed_json($c, $media_type, $json);
        $entity = JSON::decode_json($json);
        last unless $self->valid_entity($c, $entity);
        my $hal = Data::HAL->from_json($json);

        my $r_id;
        {
            my $reseller_link = ($hal->links // [])->grep(sub {
                $_->relation->eq('http://purl.org/sipwise/ngcp-api/#rel-resellers')
            });

            if ($reseller_link->size) {
                my $reseller_uri = URI->new_abs($reseller_link->at(0)->href->as_string, $c->req->uri)->canonical;
                my $resellers_uri = URI->new_abs('/api/resellers/', $c->req->uri)->canonical;
                if (0 != index $reseller_uri, $resellers_uri) {
                    $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
                    $c->response->header('Content-Language' => 'en');
                    $c->response->content_type('application/xhtml+xml');
                    $c->stash(
                        template => 'api/unprocessable_entity.tt',
                        error_message => "The link $reseller_uri cannot express a reseller relationship.",
                    );
                    last;
                }
                $r_id = $reseller_uri->rel($resellers_uri)->query_param('id');
                last unless $self->valid_id($c, $r_id);
            }
        }
        my $resource = $hal->resource;

        my $contact_form = NGCP::Panel::Form::Contact::Reseller->new;
        my %fields = map { $_->name => undef } grep { 'Text' eq $_->type || 'Email' eq $_->type } $contact_form->fields;
        for my $k (keys %{ $resource }) {
            delete $resource->{$k} unless exists $fields{$k};
            $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
                if $resource->{$k}->$_isa('DateTime');
        }
        my $result = $contact_form->run(params => $resource);
        if ($result->error_results->size) {
            $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
            $c->response->header('Content-Language' => 'en');
            $c->response->content_type('application/xhtml+xml');
            my $e = $result->error_results->map(sub {
                sprintf '%s: %s - %s', $_->name, $_->input, $_->errors->join(q())
            })->join("\n");
            $c->stash(
                template => 'api/unprocessable_entity.tt',
                error_message => "Validation failed: $e",
            );
            last;
        }

        $resource->{reseller_id} = $r_id;
        $resource->{modify_timestamp} = DateTime->now;
        $contact = $self->contact_by_id($c, $id) unless $contact;
        $contact->update($resource);
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->cache->remove($c->request->uri->canonical->as_string);
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            $hal = $self->hal_from_contact($contact);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
                Cache_Control => 'no-cache, private',
                ETag => $self->etag($hal->as_json),
                Expires => DateTime::Format::HTTP->format_datetime($self->expires),
                Last_Modified => DateTime::Format::HTTP->format_datetime($self->last_modified),
            ), $hal->as_json);
            $c->cache->set($c->request->uri->canonical->as_string, $response, { expires_at => $self->expires->epoch });
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation'); # don't cache this
            $c->response->body($response->content);
        }
    }
    return;
}

sub contact_by_id : Private {
    my ($self, $c, $id) = @_;
    return $c->model('DB')->resultset('contacts')->find({'me.id' => $id}, {prefetch => ['reseller']});
}

sub hal_from_contact : Private {
    my ($self, $contact) = @_;
    # XXX invalid 00-00-00 dates
    my %resource = $contact->get_inflated_columns;
    my $id = delete $resource{id};
    $self->last_modified(delete $resource{modify_timestamp});

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
