package NGCP::Panel::Controller::API::Interceptions;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Interception;
use UUID qw/generate unparse/;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines lawful interceptions of subscribers.';
};

sub query_params {
    return [
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
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Interceptions/;

sub resource_name{
    return 'interceptions';
}

sub dispatch_path{
    return '/api/interceptions/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-interceptions';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

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
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('InterceptDB')->txn_scope_guard;
    my $cguard = $c->model('DB')->txn_scope_guard;
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

        my ($sub, $reseller, $voip_number) = NGCP::Panel::Utils::Interception::subresnum_from_number($c, $resource->{number}, sub {
            my ($msg,$field,$response) = @_;
            $c->log->error($msg);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $response);
            return 0;
        });
        last unless($sub && $reseller);

        $resource->{reseller_id} = $reseller->id;

        $resource->{sip_username} = NGCP::Panel::Utils::Interception::username_to_regexp_pattern($c,$voip_number,$sub->username);
        $resource->{sip_domain} = $sub->domain->domain;

        if($resource->{x3_required} && (!defined $resource->{x3_host} || !defined $resource->{x3_port})) {
            $c->log->error("Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
            last;
        }
        if (defined $resource->{x3_port} && !is_int($resource->{x3_port})) {
            $c->log->error("Parameter 'x3_port' should be an integer");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Parameter 'x3_port' should be an integer");
            last;
        }

        my ($uuid_bin, $uuid_string);
        UUID::generate($uuid_bin);
        UUID::unparse($uuid_bin, $uuid_string);
        $resource->{uuid} = $uuid_string;

        $resource->{deleted} = 0;
        $resource->{create_timestamp} = $resource->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;

        my $item;
        my $dbresource = { %{ $resource } };
        $dbresource = $self->resnames_to_dbnames($dbresource);
        $dbresource->{reseller_id} = $resource->{reseller_id};
        try {
            $item = $c->model('InterceptDB')->resultset('voip_intercept')->create($dbresource);
            my $res = NGCP::Panel::Utils::Interception::request($c, 'POST', undef, {
                liid => $resource->{liid},
                uuid => $resource->{uuid},
                number => $resource->{number},
                sip_username => $resource->{sip_username},
                sip_domain => $resource->{sip_domain},
                delivery_host => $resource->{x2_host},
                delivery_port => $resource->{x2_port},
                delivery_user => $resource->{x2_user},
                delivery_password => $resource->{x2_password},
                cc_required => $resource->{x3_required},
                cc_delivery_host => $resource->{x3_host},
                cc_delivery_port => $resource->{x3_port},
            });
            die "Failed to populate capture agents\n" unless($res);
        } catch($e) {
            $c->log->error("failed to create interception: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create interception");
            last;
        }

        $guard->commit;
        $cguard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub filter_log_response {
    my ($self, $c, $response_body, $params_data) = @_;

    if (exists $params_data->{number}) {
        $params_data->{number} = '***';
    }
    $response_body //= "";
    $response_body =~ s!([+0-9]{2,})([0-9]{2})!***$2!g; # hide strings which look like a number

    return ($response_body, $params_data);
}

1;

# vim: set tabstop=4 expandtab:
