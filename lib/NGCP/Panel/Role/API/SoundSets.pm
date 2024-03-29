package NGCP::Panel::Role::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::Sems;

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
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Reseller does not exist",
                     "invalid reseller_id '$$resource{reseller_id}'");
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
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer does not exist",
                         "invalid customer_id '$$resource{contract_id}'");
            return;
        }
        unless($customer->contact->reseller_id == $reseller->id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller for customer",
                         "customer_id '$$resource{contract_id}' doesn't belong to reseller_id '$$resource{reseller_id}");
            return;
        }
    }

    if ($c->user->roles eq 'subscriberadmin' && $c->request->method ne 'POST' &&
        (!$old_resource->{contract_id} || $old_resource->{contract_id} != $c->user->account_id)) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot modify read-only sound set",
                         "Cannot modify read-only sound set that does not belong to this subscriberadmin");
            return;
    }

    if ($resource->{parent_id}) {
        my $parent = $c->model('DB')->resultset('voip_sound_sets')->find($resource->{parent_id});
        if (!$parent) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Parent sound set does not exist",
                         "Invalid parent_id '$$resource{parent_id}'");
            return;
        }
        if ($c->user->roles ne 'admin' && $reseller->id != $parent->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller for parent sound set",
                         "parent_id '$$resource{parent_id}' doesn't belong to reseller_id '$$resource{reseller_id}");
            return;
        }
        if ($c->req->method eq 'PUT' || $c->req->method eq 'PATCH') {
            my $loop = NGCP::Panel::Utils::Sounds::check_parent_chain_for_loop(
                $c, $old_resource->{id}, $resource->{parent_id}
            );
            if ($loop) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot use the parent sound set",
                             "parent_id '$$resource{parent_id}' one of the parent sound sets refers to this one as a parent");
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

    # invalidate cache of this sound set if parent is changed
    my $old_parent_id = $old_resource->{parent_id};
    my $parent_id = $resource->{parent_id};
    if ((!$old_parent_id && $parent_id) ||
         ($old_parent_id && !$parent_id) ||
         ($old_parent_id && $parent_id && $old_parent_id != $parent_id)) {
        NGCP::Panel::Utils::Sems::clear_audio_cache($c, $item->id);
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
