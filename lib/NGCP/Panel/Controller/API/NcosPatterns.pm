package NGCP::Panel::Controller::API::NcosPatterns;
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
    return 'NCOS Patterns define rules within NCOS Levels.';
};

sub query_params {
    return [
        {
            param => 'ncos_level_id',
            description => 'Filter for NCOS patterns belonging to a specific NCOS level.',
            query => {
                first => sub {
                    my $q = shift;
                    { ncos_level_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::NcosPatterns/;

sub resource_name{
    return 'ncospatterns';
}

sub dispatch_path{
    return '/api/ncospatterns/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-ncospatterns';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});



sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
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

        my $level_rs = $c->model('DB')->resultset('ncos_levels')->search({
            id => $resource->{ncos_level_id},
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $level_rs = $level_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        my $level = $level_rs->first;
        unless($level) {
            $c->log->error("invalid ncos_level_id '$$resource{ncos_level_id}' for reseller_id '$$resource{reseller_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid ncos_level_id, level does not exist");
            return;
        }

        my $dup_item = $level->ncos_pattern_lists->search({
            pattern => $resource->{pattern},
        })->first;
        if($dup_item) {
            $c->log->error("ncos pattern '$$resource{pattern}' already exists for ncos_level_id '$$resource{ncos_level_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS pattern already exists for given ncos level");
            return;
        }

        my $item;
        try {
            $item = $level->ncos_pattern_lists->create($resource);
        } catch($e) {
            $c->log->error("failed to create ncos level: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create ncos level.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
