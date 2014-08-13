package NGCP::Panel::Controller::API::Interceptions;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use UUID qw/generate unparse/;
use NGCP::Panel::Utils::DateTime;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines lawful interceptions of subscribers.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'liid',
            description => 'Filter for interceptions of a specific interception id',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.LIID' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'number',
            description => 'Filter for interceptions of a specific number (in E.164 format)',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.number' => $q };
                },
                second => sub { },
            },
        },
    ]},
);

with 'NGCP::Panel::Role::API::Interceptions';

class_has('resource_name', is => 'ro', default => 'interceptions');
class_has('dispatch_path', is => 'ro', default => '/api/interceptions/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-interceptions');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);

    unless($c->user->lawful_intercept) {
        $self->error($c, HTTP_FORBIDDEN, "Accessing user has no LI privileges.");
        return;
    }
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $num_rs = $c->model('DB')->resultset('voip_numbers')->search(
            \[ 'concat(cc,ac,sn) = ?', $resource->{number}]
        );
        unless($num_rs->first) {
            $c->log->error("invalid number '$$resource{number}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number does not exist");
            last;
        }
        $resource->{reseller_id} = $num_rs->first->reseller_id;

        my $sub = $num_rs->first->subscriber;
        unless($sub) {
            $c->log->error("invalid number '$$resource{number}', not assigned to any subscriber");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number is not active");
            last;
        }
        $resource->{sip_username} = $sub->username;
        $resource->{sip_domain} = $sub->domain->domain;

        if($resource->{x3_required} && (!defined $resource->{x3_host} || !defined $resource->{x3_port})) {
            $c->log->error("Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            last;
        }

        my ($uuid_bin, $uuid_string);
        UUID::generate($uuid_bin);
        UUID::unparse($uuid_bin, $uuid_string);
        $resource->{uuid} = $uuid_string;

        $resource->{deleted} = 0;
        $resource->{create_timestamp} = $resource->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;

        my $item;
        $resource = $self->resnames_to_dbnames($resource);
        try {
            $item = $c->model('DB')->resultset('voip_intercept')->create($resource);
        } catch($e) {
            $c->log->error("failed to create interception: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create interception.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
