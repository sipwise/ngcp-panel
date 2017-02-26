package NGCP::Panel::Role::API::MailToFaxSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::MailToFax::API;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c, $type) = @_;

    return NGCP::Panel::Form::MailToFax::API->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $rwr_form = $self->get_form($c);
    my $type = 'mailtofaxsettings';

    my $prov_subs = $item->provisioning_voip_subscriber;

    die "no provisioning_voip_subscriber" unless $prov_subs;

    my $mtf_preference = $prov_subs->voip_mail_to_fax_preference;
    unless ($mtf_preference) {
        try {
            $mtf_preference = $prov_subs->create_related('voip_mail_to_fax_preference', {});
            $mtf_preference->discard_changes; # reload
        } catch($e) {
            $c->log->error("Error creating empty mail_to_fax_preference on get");
        };
    }

    my %resource = (
            $mtf_preference ? $mtf_preference->get_inflated_columns : (),
            subscriber_id => $item->id,
        );
    delete $resource{id};
    my @secret_renew_notify;
    for my $notify ($prov_subs->voip_mail_to_fax_secrets_renew_notify->all) {
        push @secret_renew_notify, {$notify->get_inflated_columns};
    }
    $resource{secret_renew_notify} = \@secret_renew_notify;
    my @acls;
    for my $acl ($prov_subs->voip_mail_to_fax_acls->all) {
        push @acls, {$acl->get_inflated_columns};
    }
    $resource{acl} = \@acls;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );


    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { 'me.status' => { '!=' => 'terminated' } },
            { prefetch => 'provisioning_voip_subscriber',},
        );
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    return $self->item_rs($c)->search_rs({'me.id' => $id})->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $billing_subscriber_id = $item->id;
    my $prov_subs = $item->provisioning_voip_subscriber;
    die "need provisioning_voip_subscriber" unless $prov_subs;
    my $prov_subscriber_id = $prov_subs->id;
    my $secret_renew_notify_rs = $prov_subs->voip_mail_to_fax_secrets_renew_notify;
    my $acl_rs = $prov_subs->voip_mail_to_fax_acls;

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 1,
    );

    if (! exists $resource->{secret_renew_notify} ) {
        $resource->{secret_renew_notify} = [];
    }
    if (ref $resource->{secret_renew_notify} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'secret_renew_notify'. Must be an array.");
        return;
    }

    if (! exists $resource->{acl} ) {
        $resource->{acl} = [];
    }
    if (ref $resource->{acl} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'acl'. Must be an array.");
        return;
    }

    my %update_fields = %{ $resource };
    delete $update_fields{secret_renew_notify};
    delete $update_fields{acl};

    try {
        $prov_subs->delete_related('voip_mail_to_fax_preference');
        $secret_renew_notify_rs->delete;
        $acl_rs->delete;
        $prov_subs->create_related('voip_mail_to_fax_preference', \%update_fields);
        $prov_subs->discard_changes; #reload

        for my $notify (@{ $resource->{secret_renew_notify} }) {
            $secret_renew_notify_rs->create($notify);
        }
        for my $acl (@{ $resource->{acl} }) {
            $secret_renew_notify_rs->create($acl);
        }
    } catch($e) {
        $c->log->error("Error Updating mailtofaxsettings: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "mailtofaxsettings could not be updated.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
