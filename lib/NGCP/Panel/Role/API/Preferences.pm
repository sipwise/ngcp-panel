package NGCP::Panel::Role::API::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Safe::Isa qw($_isa);
use Data::Validate::IP qw/is_ipv4 is_ipv6/;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $type = $self->container_resource_type;
    my $print_type = $type;
    $print_type = "customers" if $print_type eq "contracts";
    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$print_type", href => sprintf("/api/%s/%d", $print_type, $item->id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->get_resource($c, $item, $type);

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item{
    my($self, $c, $item) = @_;
    return $self->get_resource($c, $item);
}

sub get_resource {
    my ($self, $c, $item) = @_;

    return NGCP::Panel::Utils::Preferences::prepare_resource(
        c => $c,
        schema => $c->model('DB'),
        item => $item,
        type => $self->container_resource_type,
    );

}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;
    my $type = $self->container_resource_type;

    if($type eq "domains") {
        # we actually return the domain rs here, as we can easily
        # go to dom_preferences from there
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('domains');
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('domains')->search({
                reseller_id => $c->user->reseller_id,
            });
        }
    } elsif($type eq "profiles") {
        # we actually return the profile rs here, as we can easily
        # go to prof_preferences from there
        $item_rs = $c->model('DB')->resultset('voip_subscriber_profiles');
        if($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
            $item_rs = $item_rs->search({
                'profile_set.reseller_id' => $c->user->reseller_id,
            },{
                join => 'profile_set',
            });
        }
    } elsif($type eq "subscribers" || $type eq "active") {
        if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'me.status' => { '!=' => 'terminated' }
            }, {
                join => { 'contract' => 'contact' }, #for filters
            });
        } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'me.status' => { '!=' => 'terminated' },
            }, {
                join => { 'contract' => 'contact' },
            });
        } elsif ($c->user->roles eq 'subscriberadmin') {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contract.id' => $c->user->account_id,
                'me.status' => { '!=' => 'terminated' },
            },{
                join => 'contract',
            });
        } elsif ($c->user->roles eq 'subscriber') {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'me.uuid' => $c->user->uuid,
                'me.status' => { '!=' => 'terminated' },
            },{
                join => 'contract',
            });
        }
    } elsif($type eq "peerings") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_peer_hosts');
        } else {
            return;
        }
    } elsif($type eq "resellers") {
        if ($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('resellers')->search_rs({
                'me.status' => { '!=' => 'terminated' },
            },);
        } elsif ($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('resellers')->search_rs({
                'me.id' => $c->user->reseller_id,
                'me.status' => { '!=' => 'terminated' },
            },);
        }
    } elsif($type eq "pbxdevicemodels") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('autoprov_devices');
            #don't select images
            #$item_rs = $c->model('DB')->resultset('autoprov_devices')->search_rs(
            #    undef,
            #    {
            #        'columns'
            #            => [qw/id reseller_id type vendor model front_image_type mac_image_type num_lines bootstrap_method bootstrap_uri extensions_num/]
            #    }
            #);
        } else {
            $item_rs = $c->model('DB')->resultset('autoprov_devices')->search({'reseller_id' => $c->user->reseller_id});
        }
    } elsif($type eq "pbxdeviceprofiles") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('autoprov_profiles');
        } else {
            $item_rs = $c->model('DB')->resultset('autoprov_profiles')->search({
                    'device.reseller_id' => $c->user->reseller_id
                },{
                    'join' => {'config' => 'device'},
            });
        }
    } elsif($type eq "pbxdevices") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('autoprov_field_devices');
        } else {
            $item_rs = $c->model('DB')->resultset('autoprov_field_devices')->search({
                    'device.reseller_id' => $c->user->reseller_id
                },{
                    'join' => {'profile' => {'config' => 'device'}},
            });
        }
    } elsif($type eq "contracts") {
        if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({
                'me.status' => { '!=' => 'terminated' },
                'contact.reseller_id' => { '!=' => undef },

            },{
                join => 'contact',
            });
        } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'me.status' => { '!=' => 'terminated' },
            }, {
                join => 'contact',
            });
        }
    }
    return $item_rs;
}

sub update_item {

    my ($self, $c, $item, $old_resource, $resource) = @_;

    return NGCP::Panel::Utils::Preferences::update_preferences(
        c => $c,
        schema => $c->model('DB'),
        item => $item,
        old_resource => $old_resource,
        resource => $resource,
        type => $self->container_resource_type,
        replace => uc($c->request->method) eq 'PUT',
        err_code => sub {
            my ($code, $msg) = @_;
            $self->error($c, $code, $msg);
        },
    );

}

1;
# vim: set tabstop=4 expandtab:
