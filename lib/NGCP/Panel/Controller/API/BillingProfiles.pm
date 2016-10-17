package NGCP::Panel::Controller::API::BillingProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Reseller qw();
use NGCP::Panel::Utils::Billing qw();
use Path::Tiny qw(path);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of <a href="#billingfees">Billing Fees</a> and <a href="#billingzones">Billing Zones</a> and can be assigned to <a href="#customers">Customers</a> and <a href="#contracts">System Contracts</a>.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for billing profiles belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'handle',
            description => 'Filter for billing profiles with a specific handle',
            query => {
                first => sub {
                    my $q = shift;
                    { handle => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BillingProfiles/;

sub resource_name{
    return 'billingprofiles';
}
sub dispatch_path{
    return '/api/billingprofiles/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingprofiles';
}

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
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);



sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $profiles = $self->item_rs($c);
        (my $total_count, $profiles) = $self->paginate_order_collection($c, $profiles);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $profile ($profiles->all) {
            push @embedded, $self->hal_from_profile($c, $profile, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $profile->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));

        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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
        } else {
            $resource->{reseller_id} = $c->user->contract->contact->reseller_id;
        }

        my $form = $self->get_form($c);
        $resource->{reseller_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        last unless NGCP::Panel::Utils::Reseller::check_reseller_create_item($c,$resource->{reseller_id},sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });

        my $weekday_peaktimes_to_create = [];
        last unless NGCP::Panel::Utils::Billing::prepare_peaktime_weekdays(c => $c,
            resource => $resource,
            peaktimes_to_create => $weekday_peaktimes_to_create,
            err_code => sub {
                my ($err) = @_;
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            }
        );

        my $special_peaktimes_to_create = [];
        last unless NGCP::Panel::Utils::Billing::prepare_peaktime_specials(c => $c,
            resource => $resource,
            peaktimes_to_create => $special_peaktimes_to_create,
            err_code => sub {
                my ($err) = @_;
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            }
        );

        my $billing_profile;
        try {
            $billing_profile= $schema->resultset('billing_profiles')->create($resource);
            foreach my $weekday_peaktime (@$weekday_peaktimes_to_create) {
                $billing_profile->billing_peaktime_weekdays->create($weekday_peaktime);
            }
            foreach my $special_peaktime (@$special_peaktimes_to_create) {
                $billing_profile->billing_peaktime_specials->create($special_peaktime);
            }
        } catch($e) {
            $c->log->error("failed to create billing profile: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billing profile.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_billing_profile = $self->profile_by_id($c, $billing_profile->id);
            return $self->hal_from_profile($c, $_billing_profile,$form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $billing_profile->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
