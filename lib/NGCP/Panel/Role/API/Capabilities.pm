package NGCP::Panel::Role::API::Capabilities;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;

use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::Capabilities::API;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Capabilities::API->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->{id})),
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

        my $customer_rs = NGCP::Panel::Utils::Contract::get_customer_rs(
            c => $c,
            contract_id => $c->user->account_id,
        );
        $customer_rs = $customer_rs->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            '+select' => [ 'product.class' ],
            '+as' => [ 'product_class' ],
        });
		my $customer = $customer_rs->first;

        my $cpbx = ($customer->get_column('product_class') eq 'pbxaccount') ? 1 : 0;
        $cloudpbx &= $cpbx;

        # TODO: sms and rtcengine are not specially restricted
        my $profile = $c->user->voip_subscriber_profile;
        if($profile) {
            my @attrs = map { $_->attribute->attribute } $profile->profile_attributes->all;
            if(grep(/^fax_server$/, @attrs)) {
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
