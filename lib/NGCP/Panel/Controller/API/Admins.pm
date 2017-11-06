package NGCP::Panel::Controller::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Admins/;

__PACKAGE__->set_config();


sub api_description {
    return'Defines admins to log into the system via panel or api.';
}
sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for admins belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'login',
            description => 'Filter for admins with a specific login (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { login => { like => $q  } };
                },
                second => sub {},
            },
        },
    ];
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        unless($c->user->is_master) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot create admin without master permissions");
            last;
        }
        
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        my $pass = $resource->{password};
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        delete $resource->{password};
        if(defined $pass) {
            $resource->{md5pass} = undef;
            $resource->{saltedpass} = NGCP::Panel::Utils::Admin::generate_salted_hash($pass);
        }
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $item;
        $item = $c->model('DB')->resultset('admins')->find({
            login => $resource->{login},
        });
        if($item) {
            $c->log->error("admin with login '$$resource{login}' already exists");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Admin with this login already exists");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('admins')->create($resource);
        } catch($e) {
            $c->log->error("failed to create admin: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create admin.");
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
