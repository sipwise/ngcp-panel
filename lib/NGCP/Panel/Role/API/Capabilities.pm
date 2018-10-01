package NGCP::Panel::Role::API::Capabilities;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;

use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Capabilities::API", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->{id})),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => $item,
        form => $form,
        run => 0,
    );

    $hal->resource($item);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my ($cloudpbx, $sms, $faxserver, $rtcengine, $fileshare, $mobilepush);

    $cloudpbx = $c->config->{features}->{cloudpbx} // 0;
    $sms = $c->config->{features}->{sms} // 0;
    $faxserver = $c->config->{features}->{faxserver} // 0;
    $rtcengine = $c->config->{features}->{rtcengine} // 0;
    $fileshare = $c->config->{features}->{fileshare} // 0;
    $mobilepush = $c->config->{features}->{mobilepush} // 0;

    if($c->user->roles eq "admin") {
        # nothing to be done
    } elsif($c->user->roles eq "reseller") {
        # TODO: is it correct to just check rtc_user of reseller?
        $rtcengine &= ($c->user->reseller->rtc_user // 0);
    } else {

        my $customer = $c->user->voip_subscriber->contract;
        $rtcengine &= ($customer->contact->reseller->rtc_user // 0);
        my $cpbx = ($customer->product->class eq 'pbxaccount') ? 1 : 0;
        $cloudpbx &= $cpbx;

        # TODO: sms and rtcengine are not specially restricted; should it?
        my $profile = $c->user->voip_subscriber_profile;
        if($profile) {
            my $attrs = [ map { $_->attribute->attribute } $profile->profile_attributes->all ];
            if(grep { /^fax_server$/ } @{ $attrs }) {
                $faxserver &= 1;
            } else {
                $faxserver = 0;
            }
        }
    }

    my $item_rs = [
        { id => 1, name => 'cloudpbx',  enabled => $cloudpbx },
        { id => 2, name => 'sms',       enabled => $sms },
        { id => 3, name => 'faxserver', enabled => $faxserver },
        { id => 4, name => 'rtcengine', enabled => $rtcengine },
        { id => 5, name => 'fileshare', enabled => $fileshare},
        { id => 6, name => 'mobilepush',enabled => $mobilepush},
    ];

    if($c->req->param('name')) {
        my $res = [];
        foreach my $item (@{ $item_rs }) {
            if($item->{name} eq $c->req->param('name')) {
                push @{ $res }, $item;
                last;
            }
        }
        return $res;
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    foreach my $item(@{ $item_rs }) {
        return $item if $item->{id} == $id;
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
