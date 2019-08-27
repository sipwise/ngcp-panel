package NGCP::Panel::Role::API::FaxserverSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::API::Subscribers;

sub resource_name{
    return 'faxserversettings';
}

sub get_form {
    my ($self, $c, $type) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Faxserver::API", $c);
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { 'me.status' => { '!=' => 'terminated' } },
            { prefetch => 'provisioning_voip_subscriber',},
        );
    if($c->user->roles eq "reseller" || $c->user->roles eq "ccareadmin") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'me.contract_id' => $c->user->account_id,
        });
    } elsif($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search_rs({
            'me.uuid' => $c->user->uuid,
        });
    }
    return $item_rs;
}

sub resource_from_item{
    my($self, $c, $item) = @_;

    my $billing_subscriber = NGCP::Panel::Utils::API::Subscribers::get_active_subscriber($self, $c, $item->id);
    unless($billing_subscriber) {
        $c->log->error("invalid subscriber id $item->id for fax send");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Fax subscriber not found.");
        return;
    }
    my $prov_subs = $item->provisioning_voip_subscriber;
    die "no provisioning_voip_subscriber" unless $prov_subs;

    my $fax_preference = $prov_subs->voip_fax_preference;
    unless ($fax_preference) {
        try {
            $fax_preference = $prov_subs->create_related('voip_fax_preference', {});
            $fax_preference->discard_changes; # reload
        } catch($e) {
            $c->log->error("Error creating empty fax_preference on get");
        };
    }

    my %resource = (
            $fax_preference ? $fax_preference->get_inflated_columns : (),
            subscriber_id => $item->id,
        );
    delete $resource{id};
    my @destinations;
    for my $dest ($prov_subs->voip_fax_destinations->all) {
        push @destinations, {$dest->get_inflated_columns};
    }
    $resource{destinations} = \@destinations;
    return \%resource;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
    ];
}

1;
# vim: set tabstop=4 expandtab:
