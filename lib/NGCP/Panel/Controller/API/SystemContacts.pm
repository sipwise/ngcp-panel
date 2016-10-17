package NGCP::Panel::Controller::API::SystemContacts;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a physical or legal person\'s address (postal and/or email) to be used in <a href="#contracts">System Contracts</a> (contracts for peerings and resellers).';
};

sub query_params {
    return [
        {
            param => 'email',
            description => 'Filter for contacts matching an email pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { email => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SystemContacts/;

sub resource_name{
    return 'systemcontacts';
}
sub dispatch_path{
    return '/api/systemcontacts/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-systemcontacts';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
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
        my $contacts = $self->item_rs($c);
        (my $total_count, $contacts) = $self->paginate_order_collection($c, $contacts);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $contact ($contacts->search({}, {prefetch => ['reseller']})->all) {
            push @embedded, $self->hal_from_contact($c, $contact, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $contact->id),
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





sub POST :Allow {
    my ($self, $c) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        $resource->{country}{id} = delete $resource->{country};
        $resource->{timezone}{name} = delete $resource->{timezone};
        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        $resource->{country} = $resource->{country}{id};
        $resource->{timezone} = $resource->{timezone}{name};

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $contact;
        try {
            $contact = $c->model('DB')->resultset('contacts')->create($resource);
        } catch($e) {
            $c->log->error("failed to create contact: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create contact.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            #my $_form = $self->get_form($c);
            my $_contact = $self->contact_by_id($c, $contact->id);
            return $self->hal_from_contact($c, $_contact, $form); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $contact->id));
        $c->response->body(q());
    }
    return;
}



1;

# vim: set tabstop=4 expandtab:
