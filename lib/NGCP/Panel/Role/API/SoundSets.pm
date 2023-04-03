package NGCP::Panel::Role::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Sounds;

sub resource_name{
    return 'soundsets';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_sound_sets')->search({
    },{
        join      => 'parent',
        '+select' => [ 'parent.name' ],
        '+as'     => [ 'parent_name' ],
    });
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'me.reseller_id' => $c->user->reseller_id,
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        my $contract = $c->model('DB')->resultset('contracts')->find($c->user->account_id);
        $item_rs = $item_rs->search_rs({
            -or => [
                'me.contract_id' => $c->user->account_id,
                -and => [ 'me.contract_id' => undef,
                          'me.reseller_id' => $contract->contact->reseller_id,
                          'me.expose_to_customer' => 1,
                ],
            ]
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

    # delete contract_id as it has not been exposed to 'subscriberadmin' and therefore,
    # does not need to duplicate the customer_id field
    if ($c->user->roles eq 'subscriberadmin') {
        delete $resource->{contract_id};
    }
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
    delete $resource->{parent_name};

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

    if ($c->user->roles eq 'subscriberadmin' && $c->request->method ne 'POST' &&
        (!$old_resource->{contract_id} || $old_resource->{contract_id} != $c->user->account_id)) {
            $c->log->error("Cannot modify read-only sound set that does not belong to this subscriberadmin");
            $self->error($c, HTTP_FORBIDDEN, "Cannot modify read-only sound set");
            return;
    }

    if ($resource->{parent_id}) {
        my $parent = $c->model('DB')->resultset('voip_sound_sets')->find($resource->{parent_id});
        if (!$parent) {
            $c->log->error("Invalid parent_id '$$resource{parent_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Parent sound set does not exist");
            return;
        }
        if ($c->user->roles ne 'admin' && $reseller->id != $parent->reseller_id) {
            $c->log->error("parent_id '$$resource{parent_id}' doesn't belong to reseller_id '$$resource{reseller_id}");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller for parent sound set");
            return;
        }
        if ($c->req->method eq 'PUT' || $c->req->method eq 'PATCH') {
            my $loop = NGCP::Panel::Utils::Sounds::check_parent_chain_for_loop(
                $c, $old_resource->{id}, $resource->{parent_id}
            );
            if ($loop) {
                $c->log->error("parent_id '$$resource{parent_id}' one of the parent sound sets refers to this one as a parent");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot use the parent sound set");
                return;
            }
        }
    }

    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $item->update($resource);

    if ($old_resource->{expose_to_customer} && !$resource->{expose_to_customer}) {
        NGCP::Panel::Utils::Sounds::revoke_exposed_sound_set($c, $item->id);
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
