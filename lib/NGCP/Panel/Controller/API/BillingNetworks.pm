package NGCP::Panel::Controller::API::BillingNetworks;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::BillingNetworks qw();
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD I_GET I_HEAD I_OPTIONS I_PATCH I_PUT /];
}

sub api_description {
    return 'A Billing Network is a container for a number of network ranges.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for billing networks belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },        
        {
            param => 'ip',
            description => 'Filter for billing networks containing a specific IP address',
            query => {
                first => \&NGCP::Panel::Utils::BillingNetworks::prepare_query_param_value,
                second => sub {
                    return { join => 'billing_network_blocks',
                             group_by => 'me.id', }
                             #distinct => 1 }; #not necessary if _CHECK_BLOCK_OVERLAPS was always on
                },
            },
        },
        {
            param => 'name',
            description => 'Filter for billing networks matching a name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}


use parent qw/Catalyst::Controller NGCP::Panel::Role::API::BillingNetworks/;

sub resource_name{
    return 'billingnetworks';
}
sub dispatch_path{
    return '/api/billingnetworks/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingnetworks';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => ($_ =~ m!^I_!) ? 1 : 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => ($_ =~ s!^I_!!r),
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $bns = $self->item_rs($c);

        (my $total_count, $bns) = $self->paginate_order_collection($c, $bns);
        my (@embedded, @links);
        for my $bn ($bns->all) {
            push @embedded, $self->hal_from_item($c, $bn, "billingnetworks");
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $bn->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = NGCP::Panel::Utils::DataHal->new(
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
        Allow => join(', ', @{ $allowed_methods }),
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
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $form = $self->get_form($c);
        $resource->{reseller_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "reseller_id" ],
        );
        
        last unless NGCP::Panel::Utils::Reseller::check_reseller_create_item($c,$resource->{reseller_id},sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });        
        
        last unless $self->prepare_blocks_resource($c,$resource);
        my $blocks = delete $resource->{blocks};
        
        my $bn;
        try {
            $bn = $schema->resultset('billing_networks')->create($resource);
            for my $block (@$blocks) {
                $bn->create_related("billing_network_blocks", $block);
            }
        } catch($e) {
            $c->log->error("failed to create billingnetwork: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billingnetwork.");
            return;
        };
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_bn = $self->item_by_id($c, $bn->id);
            return $self->hal_from_item($c, $_bn, "billingnetworks"); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $bn->id));
        $c->response->body(q());
    }
    return;
}

sub I_GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $bn = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, billingnetwork => $bn);

        my $hal = $self->hal_from_item($c, $bn, "billingnetworks");

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                =~ s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub I_HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub I_OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub I_PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
            ops => [qw/add replace remove copy/],
        );
        last unless $json;

        my $bn = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, billingnetwork => $bn);
        my $old_resource = $self->hal_from_item($c, $bn, "billingnetworks")->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $bn = $self->update_item($c, $bn, $old_resource, $resource, $form);
        last unless $bn;

        my $hal = $self->hal_from_item($c, $bn, "billingnetworks");
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $dset, "destinationsets");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub I_PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $bn = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, billingnetwork => $bn);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $bn->get_inflated_columns };

        my $form = $self->get_form($c);
        $bn = $self->update_item($c, $bn, $old_resource, $resource, $form);
        last unless $bn;
        
        my $hal = $self->hal_from_item($c, $bn, "billingnetworks");
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $dset, "destinationsets");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

#sub DELETE :Allow {
#    my ($self, $c, $id) = @_;
#    my $guard = $c->model('DB')->txn_scope_guard;
#    {
#        my $bn = $self->item_by_id($c, $id);
#        last unless $self->resource_exists($c, billingnetwork => $bn);
#        last unless NGCP::Panel::Utils::Reseller::check_reseller_delete_item($c,$bn->reseller_id,sub {
#            my ($err) = @_;
#            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
#        });
#        try {
#            $bn->delete;
#        } catch($e) {
#            $c->log->error("Failed to delete billingnetwork with id '$id': $e");
#            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
#            last;
#        }
#        $guard->commit;
#
#        $c->response->status(HTTP_NO_CONTENT);
#        $c->response->body(q());
#    }
#    return;
#}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
