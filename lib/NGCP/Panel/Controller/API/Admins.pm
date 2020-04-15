package NGCP::Panel::Controller::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Admins/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config();

sub api_description {
    return 'Defines admins to log into the system via panel or api.';
}

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for admins belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'login',
            description => 'Filter for admins with a specific login (wildcards possible)',
            query_type => 'string_like',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    unless($c->user->is_master) {
        $self->error($c, HTTP_FORBIDDEN, "Cannot create admin without master permissions");
        return;
    }
    my $item;
    try {
        $item = $c->model('DB')->resultset('admins')->create($resource);
    } catch($e) {
        $c->log->error("failed to create admin: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create admin.");
        return;
    }
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
