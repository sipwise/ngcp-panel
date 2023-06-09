package NGCP::Panel::Role::API::SubscriberRegistrations;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Kamailio;
use NGCP::Panel::Utils::Subscriber;

sub _item_rs {
    my ($self, $c, $filter, $opt) = @_;

    my $item_rs;

    if ($c->config->{redis}->{usrloc}) {
        # TODO: will this survive with like 1M records?

        unless (defined $filter) {
            $filter = {};
            if ($c->req->param('subscriber_id')) {
                my $sub = $c->model('DB')->resultset('voip_subscribers')->find($c->req->param('subscriber_id'));
                my $prov_subscriber = $sub->provisioning_voip_subscriber;
                my @usernames = ($prov_subscriber->username);
                my $devid_aliases = $prov_subscriber->voip_dbaliases->search(
                    {
                        is_devid => 1,
                        subscriber_id => $prov_subscriber->id
                    }
                );
                foreach my $devid ($devid_aliases->all) {
                    push @usernames, $devid->username;
                }
                if ($sub) {
                    $filter->{username} = \@usernames;
                }
                if($c->config->{features}->{multidomain}) {
                    $filter->{domain} = $sub->domain->domain;
                } else {
                    $filter->{domain} = undef;
                }
            } else {
                if ($c->config->{features}->{multidomain}) {
                    $filter->{domain} = { like => '.+' };
                } else {
                    $filter->{domain} = undef;
                }
            }

            if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
            } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
                $filter->{reseller_id} = $c->user->reseller_id;
            } elsif ($c->user->roles eq "subscriber") {
                if ($c->req->param('subscriber_id')) {
                    my $sub = $c->model('DB')->resultset('voip_subscribers')->find($c->req->param('subscriber_id'));
                    if ($sub && $sub->provisioning_voip_subscriber->id == $c->user->id) {
                        $filter->{username} = NGCP::Panel::Utils::Subscriber::get_sub_username_and_aliases($sub->provisioning_voip_subscriber);
                    } else {
                        $filter->{username} = undef;
                    }
                } else {
                    $filter->{username} = NGCP::Panel::Utils::Subscriber::get_sub_username_and_aliases($c->user);
                }
                if($c->config->{features}->{multidomain}) {
                    $filter->{domain} = $c->user->domain->domain;
                } else {
                    $filter->{domain} = undef;
                }
            } elsif ($c->user->roles eq "subscriberadmin") {
                if ($c->req->param('subscriber_id')) {
                    my $sub = $c->model('DB')->resultset('voip_subscribers')->search(
                        {
                            id => $c->req->param('subscriber_id'),
                            contract_id => $c->user->account_id
                        }
                    )->first;
                    if ($sub) {
                        $filter->{username} = NGCP::Panel::Utils::Subscriber::get_sub_username_and_aliases($sub->provisioning_voip_subscriber);
                    } else {
                        $filter->{username} = undef;
                    }
                } else {
                    my @customer_subscribers = $c->model('DB')->resultset('voip_subscribers')->search({contract_id => $c->user->account_id})->all();
                    foreach my $sub (@customer_subscribers) {
                        my $sub_username_aliases = NGCP::Panel::Utils::Subscriber::get_sub_username_and_aliases($sub->provisioning_voip_subscriber);
                        push (@{ $filter->{username} }, @$sub_username_aliases);
                    }
                }
                if($c->config->{features}->{multidomain}) {
                    $filter->{domain} = $c->user->domain->domain;
                } else {
                    $filter->{domain} = undef;
                }
            }
        }
        $item_rs = NGCP::Panel::Utils::Subscriber::get_subscriber_location_rs($c, $filter, $opt);
    } else {
        my @joins = ();
        if($c->config->{features}->{multidomain}) {
            push @joins, 'domain';
        }
        $item_rs = $c->model('DB')->resultset('location');
        if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
            $item_rs = $item_rs->search({

            },{
                join => [@joins,'subscriber'],
            });
        } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
            $item_rs = $item_rs->search({
                'contact.reseller_id' => $c->user->reseller_id
            },{
                join => [@joins, { 'subscriber' => { 'voip_subscriber' => { 'contract' => 'contact' }}} ],
            });
        } elsif($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
            $item_rs = $item_rs->search({
                'subscriber.uuid' => $c->user->uuid
            },{
                join => [@joins,'subscriber'],
            });
        }
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::LocationEntryAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);
    return unless $resource;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $resource->{subscriber_id})),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $user_agent = $resource->{user_agent};
    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );
    $resource->{user_agent} = $user_agent;

    $resource->{id} = ($item->id =~ /^\d+$/) ? int($item->id) : $item->id;

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };

    my $sub = $self->subscriber_from_item($c, $item);
    return unless($sub);
    $resource->{subscriber_id} = int($sub->id);
    $resource->{nat} = $resource->{cflags} & 64;
    if ($resource->{path}) {
        (my ($socket)) = $resource->{path} =~/;socket=([^>]+)>/;
        if ($socket) {
            $resource->{socket} = $socket;
        }
        (my ($received)) = $resource->{path} =~/;received=(.+);/;
        if ($received) {
            $resource->{received} = $received;
        }
    }

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c,{ id => $id, });
    my $item = $item_rs->find($id);
    if ($c->user->roles eq "subscriber") {
        my $sub = $self->subscriber_from_item($c, $item);
        return unless($sub->provisioning_voip_subscriber->id == $c->user->id);
    }
    return $item;
}

sub subscriber_from_item {
    my ($self, $c, $item) = @_;

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search(
        {
            '-or' => [
                    'me.username' => $item->username,
                    'voip_dbaliases.username' => $item->username,
                ],
            status => { '!=' => 'terminated' },
        },
        {
            join => { 'provisioning_voip_subscriber' => 'voip_dbaliases' },
        }
    );
    if($c->config->{features}->{multidomain}) {
        my $domain = $c->config->{redis}->{usrloc} ? $item->domain : $item->domain->domain;
        $sub_rs = $sub_rs->search({
            'domain.domain' => $domain,
        }, {
            join => 'domain',
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
        return;
    }
    return $sub;
}

sub subscriber_from_id {
    my ($self, $c, $id) = @_;

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.id' => $id,
        'me.status' => { '!=' => 'terminated' },
    });
    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $sub_rs = $sub_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    } elsif($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        $sub_rs = $sub_rs->search({
            'me.uuid' => $c->user->uuid,
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "No subscriber for subscriber_id found");
        return;
    }
    return $sub;
}

sub _item_by_aor {
    my ($self, $c, $sub, $contact) = @_;

    my $domain = $sub->provisioning_voip_subscriber->domain->domain;

    my $prov_subscriber = $sub->provisioning_voip_subscriber;
    my @usernames = ($prov_subscriber->username);
    my $devid_aliases = $prov_subscriber->voip_dbaliases->search(
        {
            is_devid => 1,
            subscriber_id => $prov_subscriber->id
        }
    );
    foreach my $devid ($devid_aliases->all) {
        push @usernames, $devid->username;
    }

    my $filter = {
        'me.contact'  => $contact,
        'me.username' => \@usernames,
        $c->config->{redis}->{usrloc}
            ? ($c->config->{features}->{multidomain}
                ? ('me.domain' => $domain)
                : ())
            : ($c->config->{features}->{multidomain}
                ? ('me.domain' => $domain)
                : ('me.domain' => undef))
    };

    if ($c->config->{redis}->{usrloc}) {
        if ($c->user->roles eq "admin") {
        } elsif ($c->user->roles eq "reseller") {
            $filter->{reseller_id} = $c->user->reseller_id;
        }
        return NGCP::Panel::Utils::Subscriber::get_subscriber_location_rs($c, $filter)->first;
    } else {
        return $self->item_rs($c)->search($filter)->first;
    }
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $create) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 1,
        #form_params => { 'use_fields_for_input_without_param' => 1 },
    );

    my $sub = $self->subscriber_from_id($c, $resource->{subscriber_id});
    unless ($sub) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Could not find a subscriber with the provided subscriber_id");
        return;
    }
    if ($item && ref $item && !$create) {
        $self->delete_item($c, $item);
    }
    my $values = $form->values;
    $values->{flags} = 0;
    $values->{cflags} = 0;
    $values->{cflags} |= 64 if($values->{nat});

    NGCP::Panel::Utils::Kamailio::create_location($c,
        $sub->provisioning_voip_subscriber,
        $values
    );
    NGCP::Panel::Utils::Kamailio::flush($c) unless $self->suppress_flush($c);

    return $item;
}

sub fetch_item {
    my ($self, $c, $resource, $form, $old_item) = @_;

    unless ($form) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing data values");
        return;
    }

    my $sub = $self->subscriber_from_id($c, $resource->{subscriber_id});
    unless ($sub) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Could not find a subscriber with the provided subscriber_id");
        return;
    }

    my $item;
    my $flush_timeout = 30;

    while ($flush_timeout) {
        $item = $self->_item_by_aor($c, $sub, $form->values->{contact});
        if ($item && (!$old_item || $item->id ne $old_item->id)) {
            last;
        }
        $item = undef;
        $flush_timeout--;
        last unless $flush_timeout;
        sleep 1;
    }

    unless ($item) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Could not find a new registration entry in the db, that might be caused by the kamailio flush mechanism, where the item has been updated successfully");
        return;
    }

    return $item;
}

sub suppress_flush {
    
    my ($self, $c) = @_;
    my $suppress_flush = $c->req->param('suppress_flush');
    if (length($suppress_flush)
        and ('1' eq $suppress_flush
        or 'true' eq lc($suppress_flush))) {
        return 1;
    }
    return 0;
    
}

sub valid_id {
    my ($self, $id) = @_;
    if (defined $id && length $id > 0) {
        return 1;
    } else {
        return;
    }
}

1;
# vim: set tabstop=4 expandtab:
