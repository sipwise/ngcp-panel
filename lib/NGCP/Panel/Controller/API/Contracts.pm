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
use HTTP::Status qw(:constants);
use JSON qw();
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Regexp::Common qw(delimited); # $RE{delimited}
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::QueryParameter;
require Catalyst::ActionRole::RequireSSL;
require URI::QueryParam;

with 'NGCP::Panel::Role::API';

class_has('dispatch_path', is => 'ro', default => '/api/contracts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-contracts');

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
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
	    last unless $resource;

    	# this is only accessible by admins, so on other roles check
        my $contract_form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $contract_form,
        );
	    my $contact = $c->model('DB')->resultset('contacts')->find($resource->{contact_id});
	    unless($contact) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid contact_id."); # TODO: log error, ...
            last;
	    }
        if($contact->reseller_id) {
            # TODO: should be allow to create customer contracts here as well? If not, reject
            # a contact with a reseller!

            #$self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid contact for system contract, must not belong to a reseller."); # TODO: log error, ...
            #last;
        }

        # TODO: do we need to use our DateTime utils for localized "now"?
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
# vim: set tabstop=4 expandtab:
