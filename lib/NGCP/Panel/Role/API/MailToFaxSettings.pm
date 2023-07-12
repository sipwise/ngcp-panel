package NGCP::Panel::Role::API::MailToFaxSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use DateTime::Format::ISO8601;
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c, $type) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::MailToFax::API", $c);
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

    if ($mtf_preference->active == 0 && ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin')) {
        $self->error($c, HTTP_FORBIDDEN, "Forbidden!");
        return;
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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
            $self->get_journal_relation_link($c, $item->id),
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

    $self->post_process_hal_resource($c, $item, \%resource, $form);
    $self->expand_fields($c, \%resource);
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
    if ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        $item_rs = $item_rs->search({
            'provisioning_voip_subscriber.id' => $c->user->id,
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
    if ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        #subscriber's can't change the 'active' field
        $resource->{active} = $prov_subs->voip_mail_to_fax_preference->active;
        if ($prov_subs->voip_mail_to_fax_preference->active == 0) {
            $self->error($c, HTTP_FORBIDDEN, "Forbidden!");
            return;
        }
    }

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

    my $last_sk_modify = $prov_subs->voip_mail_to_fax_preference
                            ? $prov_subs->voip_mail_to_fax_preference->last_secret_key_modify
                            : undef;
    my $old_secret_key = $prov_subs->voip_mail_to_fax_preference
                            ? $prov_subs->voip_mail_to_fax_preference->secret_key
                            : undef;

    if (exists $resource->{secret_key}) {
        $resource->{last_secret_key_modify} = NGCP::Panel::Utils::DateTime::current_local;
    } else {
        $last_sk_modify
            ? $resource->{last_secret_key_modify} = $last_sk_modify
            : delete $resource->{last_secret_key_modify};
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
            $acl_rs->create($acl);
        }
    } catch($e) {
        $c->log->error("Error Updating mailtofaxsettings: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "mailtofaxsettings could not be updated.");
        return;
    };

    return $item;
}

sub post_process_hal_resource {
    my ($self, $c, $item, $resource, $form) = @_;
    delete $resource->{active} if ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin');
    my $dtf = $c->model('DB')->storage->datetime_parser;
    $resource->{last_secret_key_modify} = defined $resource->{last_secret_key_modify} ?
                                    $dtf->format_datetime(DateTime::Format::ISO8601->parse_datetime($resource->{last_secret_key_modify})):
                                    undef;
    return $resource;
}

1;
# vim: set tabstop=4 expandtab:
