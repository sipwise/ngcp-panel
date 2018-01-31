package NGCP::Panel::Controller::API::LnpNumbers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


use NGCP::Panel::Utils::Lnp;
use NGCP::Panel::Utils::MySQL;

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST DELETE OPTIONS HEAD/];
}


sub api_description {
    return 'Defines LNP number entries ported to a specific <a href="#lnpcarriers">LNP Carrier</a>. You can POST numbers individually one-by-one using json. To bulk-upload numbers, specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true", like "/api/lnpnumbers/?purge_existing=true"';
};

sub query_params {
    return [
        {
            param => 'carrier_id',
            description => 'Filter for LNP numbers belonging to a specific LNP carrier',
            query => {
                first => sub {
                    my $q = shift;
                    { lnp_provider_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'number',
            description => 'Filter for LNP numbers with a specific number (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.number' => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'actual',
            description => 'Filter for LNP numbers valid at the given timestamp (YYYY-MM-DD HH:mm:ss) or the current time',
            query => undef, #dummy param
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::LnpNumbers/;

sub resource_name{
    return 'lnpnumbers';
}

sub dispatch_path{
    return '/api/lnpnumbers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-lnpnumbers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});





sub check_create_csv :Private {
    my ($self, $c) = @_;
    return 'lnp_list.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::Lnp::create_csv(
        c => $c,
    );
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $header_accept = $c->request->header('Accept');
    if(defined $header_accept && $header_accept eq 'text/csv') {
        $self->return_csv($c); #,$self->item_rs($c,$c->request->params->{'actual'});
        return;
    }
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c,
            $c->request->params->{'actual'},
            $c->request->params->{'number'});
        #my $t1 = time;
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        #my $t2 = time; print(($t2 - $t1) . "secs\n"); $t1 = time;
        #my @test = $items->all;
        #$t2 = time; print("page: " . ($t2 - $t1) . "secs\n"); $t1 = time;
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





sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource;
        my $data = $self->get_valid_raw_post_data(
            c => $c,
            media_type => [qw#application/json text/csv#],
        );
        last unless $data;

        if($c->request->header('Content-Type') eq 'text/csv') {
            $resource = $c->req->query_params;
        } else {
            last unless $self->require_wellformed_json($c, 'application/json', $data);
            $resource = JSON::from_json($data, { utf8 => 1 });
            $data = undef;
        }

        if ($data) {
            my($numbers, $fails, $text_success);
            try {
                if ($resource->{purge_existing} eq 'true') {
                    my ($start, $end);
                    $start = time;
                    NGCP::Panel::Utils::MySQL::truncate_table(
                         c => $c,
                         schema => $schema,
                         do_transaction => 0,
                         table => 'billing.lnp_numbers',
                    );
                    $schema->resultset('lnp_providers')->delete;
                    $end = time;
                    $c->log->debug("API Purging LNP entries took " . ($end - $start) . "s");
                }

                ( $numbers, $fails, $text_success ) = NGCP::Panel::Utils::Lnp::upload_csv(
                    c       => $c,
                    data    => \$data,
                    schema  => $schema,
                );

                $c->log->info( $$text_success );

                $guard->commit;

                $c->response->status(HTTP_CREATED);
                $c->response->body(q());

            } catch($e) {
                $c->log->error("failed to upload csv: $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
                last;
            };
        } else {
            delete $resource->{purge_existing};

            my $form = $self->get_form($c);
            $resource->{lnp_provider_id} = delete $resource->{carrier_id};
            last unless $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
            );
            $resource->{start} ||= undef;
            if($resource->{start} && $resource->{start} =~ /^\d{4}-\d{2}-\d{2}$/) {
                $resource->{start} .= 'T00:00:00';
            }
            $resource->{end} ||= undef;
            if($resource->{end} && $resource->{end} =~ /^\d{4}-\d{2}-\d{2}$/) {
                $resource->{end} .= 'T23:59:59';
            }

            my $carrier = $c->model('DB')->resultset('lnp_providers')->find($resource->{lnp_provider_id});
            unless($carrier) {
                $c->log->error("invalid carrier_id '$$resource{lnp_provider_id}'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "lnp carrier_id does not exist");
                last;
            }
            # revert "MT#20027: the actual lnp number must be unique across lnp_providers"

            my $item;
            try {
                $item = $c->model('DB')->resultset('lnp_numbers')->create($resource);
            } catch($e) {
                $c->log->error("failed to create lnp number: $e"); # TODO: user, message, trace, ...
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create lnp number.");
                last;
            }

            $guard->commit;

            $c->response->status(HTTP_CREATED);
            $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
            $c->response->body(q());
        }
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c) = @_;
    #my $page = $c->request->params->{page} // 1;
    #my $rows = $c->request->params->{rows} // 10;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        unless (exists $c->req->query_params->{number}) {
            $c->log->error("number query parameter required"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "number query parameter required.");
            last;
        }
        my @ids = NGCP::Panel::Utils::Lnp::terminate_lnpnumbers($c,
            $c->request->params->{'actual'},
            $c->request->params->{'number'});
        if ((scalar @ids) > 0) {
            $guard->commit;
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->body(q());
        } else {
            $self->resource_exists($c, 'lnpnumber');
        }

    }
    return;

}



1;

# vim: set tabstop=4 expandtab:
