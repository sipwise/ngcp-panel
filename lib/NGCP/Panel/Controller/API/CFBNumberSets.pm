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
    return 'Defines a collection of CallForward B-Number Sets, including the bnumbers, which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.',;
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for B-Number sets belonging to a specific subscriber',
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
            description => 'Filter for items matching a B-Number Set name pattern',
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

sub documentation_sample {
    return  {
        subscriber_id => 20,
        name => 'to_austria',
        bnumbers => [{bnumber => '43*'}],
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFBNumberSets/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $bset;

    try {
        # no checks, they are in check_resource
        my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
        my $subscriber = $b_subscriber->provisioning_voip_subscriber;

        $bset = $schema->resultset('voip_cf_bnumber_sets')->create({
                name => $resource->{name},
                mode => $resource->{mode},
                is_regex => $resource->{is_regex} // 0,
                subscriber_id => $subscriber->id,
            });
        for my $s ( @{$resource->{bnumbers}} ) {
            $bset->create_related("voip_cf_bnumbers", {
                bnumber => $s->{bnumber},
            });
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_bset = $self->item_by_id($c, $bset->id);
            return $self->hal_from_item($c, $_bset); });
        }
    } catch($e) {
        $c->log->error("failed to create cfbnumberset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfbnumberset.");
        return;
    }

    return $bset;
}

# sub POST :Allow {

# }

1;

# vim: set tabstop=4 expandtab:
