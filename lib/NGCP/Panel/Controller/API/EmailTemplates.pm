package NGCP::Panel::Controller::API::EmailTemplates;
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
    return 'Defines email templates to be send when new subscribers are created or when passwords are reset.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for email templates belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for email templates with a specific name',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.name' => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::EmailTemplates/;

sub resource_name{
    return 'emailtemplates';
}

sub dispatch_path{
    return '/api/emailtemplates/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-emailtemplates';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

        if ($c->user->roles eq "admin") {
        } elsif ($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        } elsif ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        my $item;
        $item = $c->model('DB')->resultset('email_templates')->find({
            reseller_id => $resource->{reseller_id},
            name => $resource->{name},
        });
        if($item) {
            $c->log->error("email template with name '$$resource{name}' already exists for reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Email template with this name already exists for this reseller");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('email_templates')->create($resource);
        } catch($e) {
            $c->log->error("failed to create email template: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create email template.");
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
