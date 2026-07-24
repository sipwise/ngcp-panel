package NGCP::Panel::Role::API::Subscribers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Test::More;
use POSIX qw(ceil);
use NGCP::Panel::Form;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Events;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();
use NGCP::Panel::Utils::Encryption qw();
use NGCP::Panel::Utils::Auth qw();

sub resource_name{
    return 'subscribers';
}

sub dispatch_path{
    return '/api/subscribers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscribers';
}

sub get_form {
    my ($self, $c) = @_;

    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SubscriberAPI", $c));
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SubscriberSubAdminAPI", $c));
    }
}

sub resource_from_item {
    my ($self, $c, $item, $form, $patch_mode) = @_;

    if (!$form) {
        ($form) = $self->get_form($c);
    }

    return NGCP::Panel::Utils::Subscriber::resource_from_item(
        c => $c,
        item => $item,
        patch_mode => $patch_mode,
        get_customer_code => sub {
            my ($cid) = @_;
            return $self->get_customer($c, $cid);
        },
        validate_code => sub {
            my ($resource) = @_;
            return $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
                run => 0,
            );
        },
    );
}

sub hal_from_item {
    my ($self, $c, $item, $resource, $form) = @_;
    my $is_sub = 1;
    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        $is_sub = 0;
    }
    my $is_subadm = 1;
    if($c->user->roles eq "subscriber") {
        $is_subadm = 0;
    }

    delete $resource->{password};
    delete $resource->{webpassword};
    $resource->{password} = delete $resource->{_password} if exists $resource->{_password};
    $resource->{webpassword} = delete $resource->{_webpassword} if exists $resource->{_webpassword};

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),

            # available also to subscribers
            Data::HAL::Link->new(relation => 'ngcp:subscriberpreferences', href => sprintf("/api/subscriberpreferences/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:voicemailsettings', href => sprintf("/api/voicemailsettings/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:reminders', href => sprintf("/api/reminders/?subscriber_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:callforwards', href => sprintf("/api/callforwards/%d", $item->id)),

            # only available to admins/resellers
            ($is_sub ? () : (
                ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_set_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofilesets', href => sprintf("/api/subscriberprofilesets/%d", $item->provisioning_voip_subscriber->profile_set_id))) : (),
                ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofiles', href => sprintf("/api/subscriberprofiles/%d", $item->provisioning_voip_subscriber->profile_id))) : (),
                Data::HAL::Link->new(relation => 'ngcp:domains', href => sprintf("/api/domains/%d", $item->domain->id)),
                Data::HAL::Link->new(relation => 'ngcp:calls', href => sprintf("/api/calls/?subscriber_id=%d", $item->id)),
                Data::HAL::Link->new(relation => 'ngcp:subscriberregistrations', href => sprintf("/api/subscriberregistrations/?subscriber_id=%d", $item->id)),
                #Data::HAL::Link->new(relation => 'ngcp:trustedsources', href => sprintf("/api/trustedsources/%d", $item->contract->id)),
                $self->get_journal_relation_link($c, $item->id),
            )),
            # only available to admins/resellers/subscriberadmins
            (!$is_subadm ? () : (
                Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
            )),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ 'me.status' => { '!=' => 'terminated' } });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $item_rs->search(undef,
        {
            join => { 'contract' => 'contact' }, #for filters
        });
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'contract_id' => $c->user->account_id,
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            #voip_subscriber is a provisioning.voip_subscribers relation
            #$c->user is provisioning.voip_subscribers, so we use ->voip_subscriber->id and compare to billing.voip-subscribers.
            'me.id' => $c->user->voip_subscriber->id,
        });
    } else {
        $self->error($c, HTTP_FORBIDDEN, "Invalid authentication role");
        return;
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub get_customer {
    my ($self, $c, $customer_id) = @_;

    my $customer_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        contract_id => $customer_id,
    );
    $customer_rs = $customer_rs->search({
            'contact.reseller_id' => { '-not' => undef },
            'me.id' => $customer_id,
        },{
            join => 'contact',
        });
    my @product_ids = map { $_->id; } $c->model('DB')->resultset('products')->search_rs({ 'class' => ['sipaccount','pbxaccount'] })->all;
    $customer_rs = $customer_rs->search({
        'product_id' => { -in => [ @product_ids ] },
    });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $customer_rs = $customer_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    my $customer = $customer_rs->first;
    unless($customer) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't exist.");
        return;
    }
    return $customer;
}

sub prepare_resource {
    my ($self, $c, $schema, $resource, $item, $patch_mode) = @_;

    return NGCP::Panel::Utils::Subscriber::prepare_resource(
        c => $c,
        schema => $c->model('DB'),
        resource => $resource,
        item => $item,
        err_code => sub {
            my ($code, $msg, @errors) = @_;
            $self->error($c, $code, $msg, @errors);
        },
        validate_code => sub {
            my ($r) = @_;
            my ($form) = $self->get_form($c);
            # form validation during PATCH causes
            # fields to be removed from the %resource
            # and then apply_patch() removes the fields
            # that were not a part the PATCH ops from
            # the database, therefore a copy of the resource
            # is validated instead, preserving the original one
            # when $patch_mode is enabled
            my %validate_resource = %{$r};
            return $self->validate_form(
                c => $c,
                resource => $patch_mode ? \%validate_resource : $r,
                form => $form,
            );
        },
        getcustomer_code => sub {
            my ($cid) = @_;
            my $contract = $self->get_customer($c, $cid);
            NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(
                c => $c,
                schema => $c->model('DB'),
                contract_id => $contract->id,
                skip_locked => ($c->request->header('X-Delay-Commit') ? 0 : 1),
            ) if $contract;
            return $contract;
        },
    );

}

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    $resource->{timezone} = NGCP::Panel::Utils::DateTime::get_timezone_link($c, $resource->{timezone});
}

sub update_item {
    my ($self, $c, $schema, $item, $full_resource, $resource, $form) = @_;

    return unless $self->check_write_access($c, $item->id);

    $self->process_form_resource($c, $item, $full_resource, $resource, $form);

    return NGCP::Panel::Utils::Subscriber::update_subscriber(
        c => $c,
        schema => $schema,
        item => $item,
        full_resource => $full_resource,
        resource => $resource,
        err_code => sub {
            my ($code, $msg, @errors) = @_;
            $self->error($c, $code, $msg, @errors);
        },
    );
}

sub check_write_access {
    my ($self, $c, $id) = @_;

    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            return 1;
    } elsif ($c->user->roles eq "subscriberadmin") {
        if (!$self->subscriberadmin_write_access($c, $id) && $id != $c->user->voip_subscriber->id) {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            return;
        }
    } elsif($c->user->roles eq "subscriber") {
        if ($id != $c->user->voip_subscriber->id) {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            return;
        }
    }
    return 1;
}

sub subscriberadmin_write_access {
    my ($self, $c, $id) = @_;
    if ( (( $c->config->{privileges}->{subscriberadmin}->{subscribers}
           && $c->config->{privileges}->{subscriberadmin}->{subscribers} =~/write/
          )
         ||
          ( $c->license('pbx') && $c->config->{features}->{cloudpbx}
           && $c->user->contract->product->class eq 'pbxaccount'
          ))
         &&
         $self->check_subscriber_same_customer($c, $id)
        ) {
        return 1;
    }
    return 0;
}

sub check_subscriber_same_customer {
    my ($self, $c, $id) = @_;

    my $sub = $c->model('DB')->resultset('voip_subscribers')->find($id);

    if ($sub && $sub->status ne 'terminated' && $sub->contract_id == $c->user->account_id) {
        return 1;
    }

    return 0;
}

1;
# vim: set tabstop=4 expandtab:
