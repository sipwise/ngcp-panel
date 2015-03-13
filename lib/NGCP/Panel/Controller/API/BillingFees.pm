package NGCP::Panel::Controller::API::BillingFees;
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
use Text::CSV_XS;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => ( 
    is => 'ro',
    isa => 'Str',
    default => 
        'Specifies the fees to be applied for a call if it matches the source or destination number of the call. You can POST fees individually one-by-one using json. To bulk-upload fees, specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection while specifying the the billing profile via URI parameters, like "/api/billingfees/?billing_profile_id=xx&amp;purge_existing=true"'
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
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
        },
    ]},
);

with 'NGCP::Panel::Role::API::BillingFees';

class_has('resource_name', is => 'ro', default => 'billingfees');
class_has('dispatch_path', is => 'ro', default => '/api/billingfees/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-billingfees');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
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
        (my $total_count, $fees) = $self->paginate_order_collection($c, $fees);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $fee ($fees->all) {
            push @embedded, $self->hal_from_fee($c, $fee, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $fee->id),
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
        my $schema = $c->model('DB');
        my $resource;
        my $data= $self->get_valid_raw_post_data(
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
            # csv bulk upload
            my $csv = Text::CSV_XS->new({allow_whitespace => 1, binary => 1, keep_meta_info => 1});
            my @cols = @{ $c->config->{fees_csv}->{element_order} };

            if ($resource->{purge_existing}) {
                $profile->billing_fees->delete;
            }
            my @fails = ();
            my $linenum = 0;
            my @fees = ();
            my %zones = ();

            try {
                foreach my $line(split /\r?\n/, $data) {
                    ++$linenum;
                    chomp $line;
                    next unless length $line;
                    unless($csv->parse($line)) {
                        push @fails, $linenum;
                        next;
                    }
                    my $row = {};
                    my @fields = $csv->fields();
                    unless (scalar @fields == scalar @cols) {
                        push @fails, $linenum;
                        next;
                    }
                    
                    for(my $i = 0; $i < @cols; ++$i) {
                        $row->{$cols[$i]} = $fields[$i];
                    }

                    my $k = $row->{zone}.'__NGCP__'.$row->{zone_detail};
                    unless(exists $zones{$k}) {
                        my $zone = $profile->billing_zones->find_or_create({
                                zone => $row->{zone},
                                detail => $row->{zone_detail}
                            });
                        $zones{$k} = $zone->id;
                    }
                    $row->{billing_zone_id} = $zones{$k};
                    delete $row->{zone};
                    delete $row->{zone_detail};
                    push @fees, $row;
                }
                $profile->billing_fees->populate(\@fees);

                my $text = $c->loc('Billing Fee successfully uploaded');
                if(@fails) {
                    $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
                }
                $c->log->info($text);
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
            my $zone;

            # in case of implicit zone declaration (name/detail instead of id),
            # find or create the zone
            if(!defined $resource->{billing_zone_id} &&
               defined $resource->{billing_zone_zone} &&
               defined $resource->{billing_zone_detail}) {

                $zone = $profile->billing_zones->find({
                    zone => $resource->{billing_zone_zone},
                    detail => $resource->{billing_zone_detail},
                });
                $zone = $profile->billing_zones->create({
                    zone => $resource->{billing_zone_zone},
                    detail => $resource->{billing_zone_detail},
                }) unless $zone;
                $resource->{billing_zone_id} = $zone->id;
                delete $resource->{billing_zone_zone};
                delete $resource->{billing_zone_detail};
            } elsif(defined $resource->{billing_zone_id}) {
                $zone = $profile->billing_zones->find($resource->{billing_zone_id});
            }
            unless($zone) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_zone_id'.");
                last;
            }

            last unless $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
            );


            my $fee;
            try {
                $fee = $profile->billing_fees->create($resource);
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
