package NGCP::Panel::Controller::API::CFBNumberSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFBNumberSets/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of CallForward B-Number Sets, including the bnumbers, which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.';
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
            query_type => 'string_eq',
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

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;

    try {
        my $schema = $c->model('DB');
        my $subscriber = $c->stash->{checked}->{subscriber};

        $item = $schema->resultset('voip_cf_bnumber_sets')->create({
                name => $resource->{name},
                mode => $resource->{mode},
                is_regex => $resource->{is_regex} // 0,
                subscriber_id => $subscriber->id,
            });

        for my $s ( @{$resource->{bnumbers}} ) {
            $item->create_related("voip_cf_bnumbers", {
                bnumber => $s->{bnumber},
            });
        }
    } catch($e) {
        $c->log->error("failed to create cfbnumberset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfbnumberset.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
