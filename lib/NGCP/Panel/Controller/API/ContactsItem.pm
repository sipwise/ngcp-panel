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
use HTTP::Headers::Util qw(split_header_words);
use HTTP::Status qw(
    HTTP_BAD_REQUEST
    HTTP_NO_CONTENT
    HTTP_NOT_FOUND
    HTTP_NOT_MODIFIED
    HTTP_OK
    HTTP_PRECONDITION_FAILED
    HTTP_PRECONDITION_REQUIRED
    HTTP_UNPROCESSABLE_ENTITY
    HTTP_UNSUPPORTED_MEDIA_TYPE
);
use JE qw();
use JSON qw();
use JSON::Pointer qw();
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Form::Contact::Reseller qw();
use NGCP::Panel::Utils::ValidateJSON qw();
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
            QueryParam => 'id',
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods QueryParameter)],
);

sub GET : Allow {
    my ($self, $c) = @_;
    {
        my $id = delete $c->request->query_parameters->{id};
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
        Accept_Patch => 'application/json-patch+json',
        Content_Language => 'en',
    ));
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/allowed_methods.tt', allowed_methods => $allowed_methods);
    return;
}

sub PATCH : Allow {
    my ($self, $c) = @_;
    my $media_type = 'application/json-patch+json';
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $id = delete $c->request->query_parameters->{id};
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
                $c->response->status(HTTP_PRECONDITION_FAILED);
                $c->response->header('Content-Language' => 'en');
                $c->response->content_type('application/xhtml+xml');
                $c->stash(template => 'api/precondition_failed.tt', entity_name => 'contact');
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

sub PUT : Allow {
    my ($self, $c) = @_;
    my $media_type = 'application/hal+json';
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $id = delete $c->request->query_parameters->{id};
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
                $c->response->status(HTTP_PRECONDITION_FAILED);
                $c->response->header('Content-Language' => 'en');
                $c->response->content_type('application/xhtml+xml');
                $c->stash(template => 'api/precondition_failed.tt', entity_name => 'contact');
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

sub apply_patch : Private {
    my ($self, $c, $entity, $json) = @_;
    my $patch = JSON::decode_json($json);
    for my $op (@{ $patch }) {
        my $coderef = JSON::Pointer->can($op->{op});
        die 'invalid op despite schema validation' unless $coderef;
        try {
            for ($op->{op}) {
                if ('add' eq $_ or 'replace' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                } elsif ('remove' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                } elsif ('move' eq $_ or 'copy' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                } elsif ('test' eq $_) {
                    die "test failed - path: $op->{path} value: $op->{value}\n"
                        unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                }
            }
        } catch($e) {
            $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
            $c->response->header('Content-Language' => 'en');
            $c->response->content_type('application/xhtml+xml');
            $c->stash(template => 'api/unprocessable_entity.tt', error_message => $e);
            return;
        };
    }
    return $entity;
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

sub contact_by_id : Private {
    my ($self, $c, $id) = @_;
    return $c->model('DB')->resultset('contacts')->find({'me.id' => $id}, {prefetch => ['reseller']});
}

sub etag : Private {
    my ($self, $octets) = @_;
    return sprintf '"ni:/sha3-256;%s"', sha3_256_base64($octets);
}

sub expires : Private {
    my ($self) = @_;
    return DateTime->now->clone->add(years => 1); # XXX insert product end-of-life
}

sub forbid_link_header : Private {
    my ($self, $c) = @_;
    return 1 unless $c->request->header('Link');
    $c->response->status(HTTP_BAD_REQUEST);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/forbid_link_header.tt');
    return;
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

sub require_body : Private {
    my ($self, $c) = @_;
    return 1 if $c->request->body;
    $c->response->status(HTTP_BAD_REQUEST);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/require_body.tt');
    return;
}

sub require_precondition : Private {
    my ($self, $c, $header_name) = @_;
    return 1 if $c->request->header($header_name);
    $c->response->status(HTTP_PRECONDITION_REQUIRED);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/require_precondition.tt', header_name => $header_name);
    return;
}

sub require_preference : Private {
    my ($self, $c) = @_;
    my @preference = grep { 'return' eq $_->[0] } split_header_words($c->request->header('Prefer'));
    return $preference[0][1]
        if 1 == @preference && ('minimal' eq $preference[0][1] || 'representation' eq $preference[0][1]);
    $c->response->status(HTTP_BAD_REQUEST);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/require_preference.tt');
    return;
}

sub require_valid_patch : Private {
    my ($self, $c, $json) = @_;
    my $js
      = path($c->path_to(qw(share static js api tv4.js)))->slurp
      . "\nvar schema = "
      . path($c->path_to(qw(share static js api json-patch.json)))->slurp
      . ";\nvar data = "
      . $json # code injection prevented by asserting well-formedness
      . ";\ntv4.validate(data, schema);";
    my $je = JE->new;
    unless ($je->eval($js)) {
        die "generic JavaScript error: $@" if $@;
        $c->response->status(HTTP_BAD_REQUEST);
        $c->response->header('Content-Language' => 'en');
        $c->response->content_type('application/xhtml+xml');
        $c->stash(
            template => 'api/valid_entity.tt',
            media_type => 'application/json-patch+json',
            error_message => JSON::to_json(
                { map { $_ => $je->{tv4}{error}{$_}->value } qw(dataPath message schemaPath) },
                { canonical => 1, pretty => 1, }
            )
        );
        return;
    };
    return 1;
}

sub require_wellformed_json : Private {
    my ($self, $c, $media_type, $patch) = @_;
    try {
        NGCP::Panel::Utils::ValidateJSON->new($patch);
    } catch($e) {
        $c->response->status(HTTP_BAD_REQUEST);
        $c->response->header('Content-Language' => 'en');
        $c->response->content_type('application/xhtml+xml');
        $c->stash(template => 'api/valid_entity.tt', media_type => $media_type, error_message => $e);
        return;
    };
    return 1;
}

sub resource_exists : Private {
    my ($self, $c, $entity_name, $resource) = @_;
    return 1 if $resource;
    $c->response->status(HTTP_NOT_FOUND);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/not_found.tt', entity_name => $entity_name);
    return;
}

sub valid_entity : Private {
    my ($self, $c, $entity) = @_;
    my $js
        = path($c->path_to(qw(share static js api tv4.js)))->slurp
        . "\nvar schema = "
        . path($c->path_to(qw(share static js api properties contacts-item.json)))->slurp
        . ";\nvar data = "
        . JSON::to_json($entity, { canonical => 1, pretty => 1, utf8 => 1, })
        . ";\ntv4.validate(data, schema);";
    my $je = JE->new;
    unless ($je->eval($js)) {
        die "generic JavaScript error: $@" if $@;
        $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
        $c->response->header('Content-Language' => 'en');
        $c->response->content_type('application/xhtml+xml');
        $c->stash(
            template => 'api/unprocessable_entity.tt',
            error_message => JSON::to_json(
                { map { $_ => $je->{tv4}{error}{$_}->value } qw(dataPath message schemaPath) },
                { canonical => 1, pretty => 1, }
            )
        );
        return;
    }
    return 1;
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

sub valid_media_type : Private {
    my ($self, $c, $media_type) = @_;
    return 1 if $c->request->header('Content-Type') && 0 == index $c->request->header('Content-Type'), $media_type;
    $c->response->status(HTTP_UNSUPPORTED_MEDIA_TYPE);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/valid_media_type.tt', media_type => $media_type);
    return;
}

sub valid_precondition : Private {
    my ($self, $c, $etag, $entity_name) = @_;
    my $if_match = $c->request->header('If-Match');
    return 1 if '*' eq $if_match || grep {$etag eq $_} Data::Record->new({
        split  => qr/\s*,\s*/, unless => $RE{delimited}{-delim => q(")},
    })->records($if_match);
    $c->response->status(HTTP_PRECONDITION_FAILED);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/precondition_failed.tt', entity_name => $entity_name);
    return;
}

sub end : Private {
    my ($self, $c) = @_;
    $c->forward(qw(Controller::Root render));
    $c->response->content_type('')
        if $c->response->content_type =~ qr'text/html'; # stupid RenderView getting in the way
use Carp qw(longmess); use DateTime::Format::RFC3339 qw(); use Data::Dumper qw(Dumper); use Convert::Ascii85 qw();
    if (@{ $c->error }) {
        my $incident = DateTime->from_epoch(epoch => Time::HiRes::time);
        my $incident_id = sprintf '%X', $incident->strftime('%s%N');
        my $incident_timestamp = DateTime::Format::RFC3339->new->format_datetime($incident);
        local $Data::Dumper::Indent = 1;
        local $Data::Dumper::Useqq = 1;
        local $Data::Dumper::Deparse = 1;
        local $Data::Dumper::Quotekeys = 0;
        local $Data::Dumper::Sortkeys = 1;
        my $crash_state = join "\n", @{ $c->error }, longmess, Dumper($c), Dumper($c->config);
        $c->log->error(
            "Exception id $incident_id at $incident_timestamp crash_state:" .
            ($crash_state ? ("\n" . $crash_state) : ' disabled')
        );
        $c->clear_errors;
        $c->stash(
            exception_incident => $incident_id,
            exception_timestamp => $incident_timestamp,
            template => 'api/internal_server_error.tt'
        );
        $c->response->status(500);
        $c->response->content_type('application/xhtml+xml');
        $c->detach($c->view);
    }
}
