package NGCP::Panel::Role::API::PbxUsers;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;
use HTTP::Status qw(:constants);

sub item_name {
    return 'pbxuser';
}

sub resource_name {
    return 'pbxusers';
}

sub dispatch_path {
    return '/api/pbxusers/';
}

sub relation {
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxusers';
}

sub get_form {
    my ($self, $c) = @_;

    my $form = (NGCP::Panel::Form::get("NGCP::Panel::Form::Pbx::UserAPI", $c));
    print "GOT FORM: $form\n";
    return $form
}

sub _item_rs {
    my ($self, $c, $type) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({
            'me.status' => { '!=' => 'terminated' },
            'product.class' => 'pbxaccount',
            'provisioning_voip_subscriber.is_pbx_group' => 0,
        },{
            join => [
                { 'contract' => 'contact' },
                { 'contract' => 'product'},
                'provisioning_voip_subscriber',
            ],
        });
    if ($c->user->roles eq 'reseller' || $c->user->roles eq 'ccare') {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    } elsif ($c->user->roles eq 'subscriberadmin') {
        $item_rs = $item_rs->search({
            'contract_id' => $c->user->account_id,
        });
    } elsif ($c->user->roles eq 'subscriber') {
        $item_rs = $item_rs->search({
            'contract_id' => $c->user->account_id,
        });
    }
    return $item_rs;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource;
    my $prov_sub = $item->provisioning_voip_subscriber;

    $resource{id} = int($item->id);

    if ($item->primary_number) {
        $resource{primary_number}->{cc} = $item->primary_number->cc;
        $resource{primary_number}->{ac} = $item->primary_number->ac;
        $resource{primary_number}->{sn} = $item->primary_number->sn;
        $resource{primary_number}->{number_id} = int($item->primary_number->id);
    }

    my $display_name_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c,
        attribute => 'display_name',
        prov_subscriber => $prov_sub,
    )->first;

    $resource{display_name} = $display_name_pref ? $display_name_pref->value : undef;
    $resource{pbx_extension} = $prov_sub->pbx_extension;
    $resource{username} = $prov_sub->username;
    $resource{domain} = $prov_sub->domain->domain;

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    return \%resource;
}

1;
# vim: set tabstop=4 expandtab:
