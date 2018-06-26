package NGCP::Panel::Controller::API::CFBNumberSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of CallForward BNumber Sets, including their b-number, which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.',;
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for b-number sets belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'voip_subscriber.id' => $q };
                },
                second => sub {
                    return { join => {subscriber => 'voip_subscriber'}};
                },
            },
        },
        {
            param => 'name',
            description => 'Filter for items matching a b-number set name pattern',
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

# sub documentation_sample {
#     return  {
#         subscriber_id => 20,
#         name => 'from_alice',
#         bnumbers => [{bnumber => 'alice'}],
#     };
# }

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFBNumberSets/;

sub resource_name{
    return 'cfbnumbersets';
}

sub dispatch_path{
    return '/api/cfbnumbersets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cfbnumbersets';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

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

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $bset;

        if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
            $resource->{subscriber_id} = $c->user->voip_subscriber->id;
        } elsif(!defined $resource->{subscriber_id}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
            last;
        }

        my $b_subscriber = $schema->resultset('voip_subscribers')->find({
                id => $resource->{subscriber_id},
            });
        unless($b_subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
            last;
        }
        my $subscriber = $b_subscriber->provisioning_voip_subscriber;
        unless($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
            last;
        }
        if (! exists $resource->{bnumbers} ) {
            $resource->{bnumbers} = [];
        }
        if (ref $resource->{bnumbers} ne "ARRAY") {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'bnumbers'. Must be an array.");
            last;
        }
        try {

            $bset = $schema->resultset('voip_cf_bnumber_sets')->create({
                    name => $resource->{name},
                    mode => $resource->{mode},
                    subscriber_id => $subscriber->id,
                });
            for my $s ( @{$resource->{bnumbers}} ) {
                $bset->create_related("voip_cf_bnumbers", {
                    bnumber => $s->{bnumber},
                });
            }
        } catch($e) {
            $c->log->error("failed to create cfbnumberset: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfbnumberset.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_bset = $self->item_by_id($c, $bset->id);
            return $self->hal_from_item($c, $_bset); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $bset->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
