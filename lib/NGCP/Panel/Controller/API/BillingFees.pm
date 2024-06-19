package NGCP::Panel::Controller::API::BillingFees;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Billing;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies the fees to be applied for a call if it matches the source or destination number of the call. You can POST fees individually one-by-one using json. To bulk-upload fees, specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection while specifying the billing profile via URI parameters, like "/api/billingfees/?billing_profile_id=xx&amp;purge_existing=true"';
}

sub query_params {
    return [
        {
            param => 'billing_profile_id',
            description => 'Filter for fees belonging to a specific billing profile',
            query => {
                first => sub {
                    my $q = shift;
                    { billing_profile_id => $q };
                },
                second => sub {},
            },
        },{
            param => 'billing_zone_id',
            description => 'Filter for fees of a specific billing zone',
            query => {
                first => sub {
                    my $q = shift;
                    { billing_zone_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BillingFees/;

sub resource_name{
    return 'billingfees';
}

sub dispatch_path{
    return '/api/billingfees/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingfees';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    unless(defined $c->request->header('Content-Type') &&
      $c->request->header('Content-Type') eq 'text/csv') {
        $self->log_request($c);
    }
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $fees = $self->item_rs($c);
        (my $total_count, $fees, my $fees_rows) = $self->paginate_order_collection($c, $fees);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $fee (@$fees_rows) {
            push @embedded, $self->hal_from_fee($c, $fee, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $fee->id),
            );
        }
        $self->expand_collection_fields($c, \@embedded);
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

        my $reseller_id;
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $reseller_id = $c->user->reseller_id;
        }
        unless($resource->{billing_profile_id}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing parameter 'billing_profile_id'.");
            last;
        }
        my $profile = $schema->resultset('billing_profiles')->find($resource->{billing_profile_id});
        unless($profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }
        if($c->user->roles ne "admin" && $profile->reseller_id != $reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }

        if ($data) {
            if ($resource->{purge_existing}) {
                $profile->billing_fees->delete;
                $profile->billing_fees_raw->delete;
            }

            try {
                (my($fees, $fails, $text_success)) = NGCP::Panel::Utils::Billing::process_billing_fees(
                    c       => $c,
                    data    => \$data,
                    profile => $profile,
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

            my $zone = $self->get_billing_zone($c,$profile,$resource);
            unless($zone) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_zone_id'.");
                last;
            }
            $resource->{match_mode} = 'regex_longest_pattern' unless $resource->{match_mode};
            last unless $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
            );


            my $fee;
            try {
                $fee = NGCP::Panel::Utils::Billing::insert_unique_billing_fees(
                    c => $c,
                    schema => $schema,
                    profile => $profile,
                    fees => [$resource],
                    return_created => 1,
                )->[0];
            } catch($e) {
                $c->log->error("failed to create billing fee: $e"); # TODO: user, message, trace, ...
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billing fee.");
                last;
            }
            $guard->commit;

            $c->response->status(HTTP_CREATED);
            $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $fee->id));
            $c->response->body(q());
            last;
        }

    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
