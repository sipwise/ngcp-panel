package NGCP::Panel::Role::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Admin;

sub resource_name{
    return 'admins';
}

sub dispatch_path{
    return '/api/admins/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-admins';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('admins');
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id
        });
    }


    if($c->user->is_master || $c->user->is_superuser) {
        # return all (or all of reseller) admins
    } else {
        # otherwise, only return the own admin if master is not set
        $item_rs = $item_rs->search({
            id => $c->user->id,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Reseller", $c);
    }
    return $form;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    my $adm = $c->user->roles eq "admin";
    return [
        $adm ? NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)) : (),    
    ];
}

#we don't use update_item for the admins now.
sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    $resource->{contract_id} //= undef;
    my $pass = $resource->{password};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    delete $resource->{password};
    if(defined $pass) {
        $resource->{md5pass} = undef;
        $resource->{saltedpass} = NGCP::Panel::Utils::Admin::generate_salted_hash($pass);
    }

    if($c->user->roles eq "reseller" && $resource->{reseller_id} != $c->user->reseller_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
        return;
    }

    if($old_resource->{login} eq NGCP::Panel::Utils::Admin::get_special_admin_login()) {
        my $active = $resource->{is_active};
        $resource = $old_resource;
        $resource->{is_active} = $active;
    }

    if($old_resource->{reseller_id} != $resource->{reseller_id}) {
        unless($c->model('DB')->resultset('resellers')->find($resource->{reseller_id})) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }

    if($old_resource->{login} ne $resource->{login}) {
        my $rs = $self->item_rs($c);
        if($rs->find({ login => $resource->{login} })) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'login', admin with this login already exists");
            return;
        }
    }

    $item->update($resource);
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
