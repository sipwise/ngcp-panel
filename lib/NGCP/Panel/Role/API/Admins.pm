package NGCP::Panel::Role::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Admin;

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

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;
    delete $resource{md5pass};
    delete $resource{saltedpass};

    my $adm = $c->user->roles eq "admin";

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf('%s', $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            $adm ? Data::HAL::Link->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)) : (),
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

    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $rs = $self->item_rs($c);
    return $rs->find($id);
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

    if($old_resource->{login} eq NGCP::Panel::Utils::Admin::get_special_admin_login()) {
        my $active = $resource->{is_active};
        $resource = $old_resource;
        $resource->{is_active} = $active;
    }

    if($c->user->roles eq "reseller" && $resource->{reseller_id} != $c->user->reseller_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
        return;
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
