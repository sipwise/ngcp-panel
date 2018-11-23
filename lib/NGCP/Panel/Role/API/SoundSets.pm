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

sub post_process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    #Currently actual field is contract_id, as it is specified in the form and thus in the doc
    #But we will keep customer_id for backward compatibility
    $resource->{customer_id} = $resource->{contract_id};
    return $resource;
}

sub pre_process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    #For backward compatibility. We always showed contract_id in generated API docs, as we used datatable field contract
    #but considered only customer_id value.
    #So now we allow both, and one documented (contract_id) has higher priority
    my $customer_id = delete $resource->{customer_id};
    $resource->{contract_id} //= $customer_id;
    return $resource;
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    } elsif ($c->user->roles eq "subscriberadmin") {
        $resource->{contract_id} = $c->user->account_id;
        $resource->{reseller_id} = $c->user->contract->contact->reseller_id;
    }
    $resource->{contract_default} //= 0;
    return $resource;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

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
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
