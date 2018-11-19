package NGCP::Panel::Role::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub resource_name{
    return 'soundsets';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_sound_sets');
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'reseller_id' => $c->user->reseller_id,
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search_rs({
                'contract_id' => $c->user->account_id,
            });
    } else {
        return;  # subscriber role not allowed
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Sound::AdminSetAPI", $c);
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Sound::ResellerSetAPI", $c);
    } elsif ($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Sound::SubadminSetAPI", $c);
    }
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    my $adm = $c->user->roles eq "admin";
    return [
        Data::HAL::Link->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)),
        $item->contract_id ? Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)) : (),
        Data::HAL::Link->new(relation => 'ngcp:soundfiles', href => sprintf("/api/soundfiles/?set_id=%d", $item->id)),
    ];
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $resource->{contract_id} = delete $resource->{customer_id};
    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    } elsif ($c->user->roles eq "subscriberadmin") {
        $resource->{contract_id} = $c->user->account_id;
        $resource->{reseller_id} = $c->user->contract->contact->reseller_id;
    }
    my $reseller = $c->model('DB')->resultset('resellers')->find({
        id => $resource->{reseller_id},
    });
    unless($reseller) {
        $c->log->error("invalid reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Reseller does not exist");
        return;
    }
    my $customer;
    if(defined $resource->{contract_id}) {
        $customer = $c->model('DB')->resultset('contracts')->find({
            id => $resource->{contract_id},
            'contact.reseller_id' => { '!=' => undef },
        },{
            join => 'contact',
        });
        unless($customer) {
            $c->log->error("invalid customer_id '$$resource{contract_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer does not exist");
            return;
        }
        unless($customer->contact->reseller_id == $reseller->id) {
            $c->log->error("customer_id '$$resource{contract_id}' doesn't belong to reseller_id '$$resource{reseller_id}"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller for customer");
            return;
        }
    }

    $resource->{contract_default} //= 0;

    my $copy_from_default_params =  { map {$_ => delete $resource->{$_}} (qw/copy_from_default loopplay override language/) };
    $item->update($resource);
    if ($copy_from_default_params->{copy_from_default}) {
        my $error;
        my $handles_rs = NGCP::Panel::Utils::Sounds::get_handles_rs(c => $c, set_rs => $item);
        NGCP::Panel::Utils::Sounds::apply_default_soundset_files(
            c          => $c,
            lang       => $copy_from_default_params->{language},
            set_id     => $item->id,
            handles_rs => $handles_rs,
            loopplay   => $copy_from_default_params->{loopplay},
            override   => $copy_from_default_params->{override},
            error_ref  => \$error,
        );
    }

    if($item->contract_id && $item->contract_default && !$old_resource->{contract_default}) {
        $c->model('DB')->resultset('voip_sound_sets')->search({
            reseller_id => $item->reseller_id,
            contract_id => $item->contract_id,
            contract_default => 1,
            id => { '!=' => $item->id },
        })->update({ contract_default => 0 });

        foreach my $bill_subscriber($item->contract->voip_subscribers->all) {
            my $prov_subscriber = $bill_subscriber->provisioning_voip_subscriber;
            if($prov_subscriber) {
                my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, prov_subscriber => $prov_subscriber, attribute => 'contract_sound_set',
                );
                unless($pref_rs->first) {
                    $pref_rs->create({ value => $item->id });
                }
            }
        }
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
