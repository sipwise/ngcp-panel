package NGCP::Panel::Controller::API::Contracts;
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
    HTTP_CREATED
    HTTP_NOT_MODIFIED
    HTTP_OK
    HTTP_UNPROCESSABLE_ENTITY
    HTTP_UNSUPPORTED_MEDIA_TYPE
);
use JE qw();
use JSON qw();
use MooseX::ClassAttribute qw(class_has);
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

class_has('dispatch_path', is => 'ro', default => '/api/contracts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-contracts');
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
        my $contracts = $c->model('DB')->resultset('contracts');
        $self->last_modified($contracts->get_column('modify_timestamp')->max_rs->single->modify_timestamp);
        my (@embedded, @links);
        for my $contract ($contracts->search({}, {order_by => {-asc => 'me.id'}, prefetch => ['contact']})->all) {
            push @embedded, $self->hal_from_contract($contract);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:contracts',
                href     => sprintf('/api/contracts/?id=%d', $contract->id),
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
                Data::HAL::Link->new(relation => 'self', href => '/api/contracts/'),
                @links,
            ]
        );
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-contracts)"|rel="item $1"|;
                s/rel=self/rel="collection self"/;
                $_
            } $hal->http_headers),
            $hal->http_headers,
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
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-contracts',
        Content_Language => 'en',
    ));
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/allowed_methods.tt', allowed_methods => $allowed_methods);
    return;
}

sub POST : Allow {
    my ($self, $c) = @_;
    my $media_type = 'application/hal+json';
    {
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, $media_type);
        last unless $self->require_body($c);
        my $json = do { local $/; $c->request->body->getline }; # slurp
        last unless $self->require_wellformed_json($c, $media_type, $json);
        last unless $self->valid_entity($c, $json);
        my $hal = Data::HAL->from_json($json);

        my $contact_id;
        {
            my $contact_link = ($hal->links // [])->grep(sub {
                $_->relation->eq('http://purl.org/sipwise/ngcp-api/#rel-contacts')
            });

            if ($contact_link->size) {
                my $contact_uri = URI->new_abs($contact_link->at(0)->href->as_string, $c->req->uri)->canonical;
                my $contacts_uri = URI->new_abs('/api/contacts/', $c->req->uri)->canonical;
                if (0 != index $contact_uri, $contacts_uri) {
                    $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
                    $c->response->header('Content-Language' => 'en');
                    $c->response->content_type('application/xhtml+xml');
                    $c->stash(
                        template => 'api/unprocessable_entity.tt',
                        error_message => "The link $contact_uri cannot express a contact relationship.",
                    );
                    last;
                }
                $contact_id = $contact_uri->rel($contacts_uri)->query_param('id');
                last unless $self->valid_id($c, $contact_id);
            }
        }
        my $resource = $hal->resource;

        my %fields = map { $_ => undef } qw(external_id status);
        for my $k (keys %{ $resource }) {
            delete $resource->{$k} unless exists $fields{$k};
            $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
                if $resource->{$k}->$_isa('DateTime');
        }

        $resource->{contact_id} = $contact_id;
        my $now = DateTime->now;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $contract = $c->model('DB')->resultset('contracts')->create($resource);

        $c->cache->remove($c->request->uri->canonical->as_string);
        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/api/contracts/?id=%d', $contract->id));
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

sub forbid_link_header : Private {
    my ($self, $c) = @_;
    return 1 unless $c->request->header('Link');
    $c->response->status(HTTP_BAD_REQUEST);
    $c->response->header('Content-Language' => 'en');
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/forbid_link_header.tt');
    return;
}

sub hal_from_contract : Private {
    my ($self, $contract) = @_;
    # XXX invalid 00-00-00 dates
    my %resource = $contract->get_inflated_columns;
    my $id = delete $resource{id};

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => '/api/contracts/'),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => "/api/contracts/?id=$id"),
            $contract->contact
                ? Data::HAL::Link->new(
                    relation => 'ngcp:contacts',
                    href => sprintf('/api/contacts/?id=%d', $contract->contact_id),
                ) : (),
        ],
        relation => 'ngcp:contracts',
    );

    my %fields = map { $_ => undef } qw(external_id status);
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

sub require_wellformed_json : Private {
    my ($self, $c, $media_type, $patch) = @_;
    try {
        NGCP::Panel::ValidateJSON->new($patch);
    } catch($e) {
        $c->response->status(HTTP_BAD_REQUEST);
        $c->response->header('Content-Language' => 'en');
        $c->response->content_type('application/xhtml+xml');
        $c->stash(template => 'api/valid_entity.tt', media_type => $media_type, error_message => $e);
        return;
    };
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

sub valid_entity : Private {
    my ($self, $c, $entity) = @_;
    my $js
        = path($c->path_to(qw(share static js tv4.js)))->slurp
        . "\nvar schema = "
        . path($c->path_to(qw(share static js contracts-item.json)))->slurp
        . ";\nvar data = "
        . $entity
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
