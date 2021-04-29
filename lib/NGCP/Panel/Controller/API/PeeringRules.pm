package NGCP::Panel::Controller::API::PeeringRules;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Peering;

__PACKAGE__->set_config({
    own_transaction_control => { POST => 1 },
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines outbound peering rules.';
};

sub query_params {
    return [
        {
            param => 'group_id',
            description => 'Filter for peering group',
            query => {
                first => sub {
                    my $q = shift;
                    { group_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'description',
            description => 'Filter for peering rules description',
            query => {
                first => sub {
                    my $q = shift;
                    { description => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'enabled',
            description => 'Filter for peering rules enabled flag',
            query => {
                first => sub {
                    my $q = shift;
                    { enabled =>  $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringRules/;

sub resource_name{
    return 'peeringrules';
}

sub dispatch_path{
    return '/api/peeringrules/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-peeringrules';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    my $item;

    my $dup_item = $schema->resultset('voip_peer_rules')->find({
        group_id => $resource->{group_id},
        caller_pattern => $resource->{caller_pattern} ? $resource->{caller_pattern} =~ s/\\\\/\\/gr : undef,
        callee_pattern => $resource->{callee_pattern} ? $resource->{callee_pattern} =~ s/\\\\/\\/gr : '',
        callee_prefix => $resource->{callee_prefix} // '',
    });

    if ($dup_item) {
        $c->log->error("peering rule already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule already exists");
        return;
    }

    try {
        $item = $schema->resultset('voip_peer_rules')->create($resource);
    } catch($e) {
        $c->log->error("failed to create rewriterule: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering rule.");
        return;
    }

    $guard->commit;
    NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
