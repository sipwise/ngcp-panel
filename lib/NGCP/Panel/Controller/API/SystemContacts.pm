package NGCP::Panel::Controller::API::SystemContacts;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD I_GET I_HEAD I_OPTIONS I_PATCH I_PUT I_DELETE /];
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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::SystemContacts/;

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
            Args => ($_ =~ m!^I_!) ? 1 : 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => ($_ =~ s!^I_!!r),
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
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

sub I_GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);

        my $hal = $self->hal_from_contact($c, $contact);

        # TODO: we don't need reseller stuff here!
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub I_HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub I_OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub I_PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $old_resource = { $contact->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $contact = $self->update_contact($c, $contact, $old_resource, $resource, $form);
        last unless $contact;

        my $hal = $self->hal_from_contact($c, $contact, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_contact($c, $contact, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub I_PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $contact->get_inflated_columns };

        my $form = $self->get_form($c);
        $contact = $self->update_contact($c, $contact, $old_resource, $resource, $form);
        last unless $contact;

        my $hal = $self->hal_from_contact($c, $contact, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_contact($c, $contact, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub I_DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $contract_rs = $c->model('DB')->resultset('contracts')->search({
            contact_id => $id,
            status => { '!=' => 'terminated' },
        });
        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            contact_id => $id,
            status => { '!=' => 'terminated' },
        }); # hypotecial, but for the sake of symmetry with customer contacts
        if ($contract_rs->first or $subscriber_rs->first) { #2. if active contracts or subscribers -> error
            $self->error($c, HTTP_LOCKED, "Contact is still in use.");
            last;
        } else {
            $contract_rs = $c->model('DB')->resultset('contracts')->search({
                contact_id => $id,
                status => { '=' => 'terminated' },
            });
            $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                contact_id => $id,
                status => { '=' => 'terminated' },
            }); # hypotecial, but for the sake of symmetry with customer contacts
            if ($contract_rs->first or $subscriber_rs->first) { #1. terminate if terminated contracts or subscribers
                $c->log->debug("terminate contact id ".$contact->id);
                try {
                    $contact->update({
                        status => "terminated",
                        terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
                    });
                    $contact->discard_changes();
                } catch($e) {
                    $c->log->error("Failed to terminate contact id '".$contact->id."': $e");
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
                    last;
                };
                my $form = $self->get_form($c);
                my $hal = $self->hal_from_contact($c, $contact, $form);
                last unless $self->add_update_journal_item_hal($c,$hal);
            } else { #3. delete otherwise
                last unless $self->add_delete_journal_item_hal($c,sub {
                    my $self = shift;
                    my ($c) = @_;
                    my $_form = $self->get_form($c);
                    return $self->hal_from_contact($c, $contact, $_form); });
                $c->log->debug("delete contact id ".$contact->id);
                $contact->delete;
            }
        }
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
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
