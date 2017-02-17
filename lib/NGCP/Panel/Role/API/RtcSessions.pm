package NGCP::Panel::Role::API::RtcSessions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;

use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Rtc;

sub get_form {
    my ($self) = @_;

    #return NGCP::Panel::Form::Rtc::NetworksAdmin->new;
    return;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $resource = { 
            subscriber_id => $item->subscriber->voip_subscriber->id,  # this may be confusing but we store the provisioning-subscriber-id but show the billing one
            rtc_network_tag => $item->rtc_network_tag,
        };

    my $rtc_session = NGCP::Panel::Utils::Rtc::get_rtc_session(
        config => $c->config,
        item => $item,
        err_code => sub {
            my ($msg, $debug) = @_;
            $c->log->debug($debug) if $debug;
            $c->log->warn($msg);
            return;
        });
    if ($rtc_session) {
        $resource->{rtc_browser_token} = $rtc_session->{data}{token};
        $resource->{rtc_app_name} = $rtc_session->{data}{app}{name} if $rtc_session->{data}{app}{name};
    } else {
        # here either delete our DB entry, or recreate it accordingly
        $item->delete;
        return;
    }

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->voip_subscriber->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('rtc_session');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => {subscriber => { voip_subscriber => { contract => 'contact' }}},
        });
    } else {
        $item_rs = $item_rs->search({
            'subscriber.id' => $c->user->id,
        },{
            join => 'subscriber',
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
