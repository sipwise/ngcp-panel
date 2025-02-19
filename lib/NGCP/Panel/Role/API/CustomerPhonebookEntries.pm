package NGCP::Panel::Role::API::CustomerPhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Phonebook;

sub resource_name {
    return 'customerphonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $params = $c->req->params;

    my $item_rs = $c->model('DB')->resultset('contract_phonebook');

    if ($c->req->method eq 'GET' && $params->{include}) {
        if ($params->{include} eq 'all') {
            $item_rs = $c->model('DB')->resultset('v_contract_phonebook');
        } elsif ($params->{include} eq 'shared') {
            $item_rs = $c->model('DB')->resultset('v_contract_shared_phonebook');
        } elsif ($params->{include} eq 'reseller') {
            $item_rs = $c->model('DB')->resultset('v_contract_reseller_phonebook');
        }
    }

    if ($c->user->roles eq 'reseller' || $c->user->roles eq 'ccare') {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    } elsif ($c->user->roles eq 'subscriberadmin') {
        $item_rs = $item_rs->search({
            'contract_id' => $c->user->account_id,
        });
    } 

    return $item_rs;
}

sub get_item_id {
    my ($self, $c, $item, $resource, $form, $params) = @_;
    return blessed $item ? $item->id : $item->{id};
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if is_int($id) || $id =~ /^[csr\d]+$/;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI");
    return;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->search({ 'me.id' => $id })->first;
}

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::CustomerAPI", $c);
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{customer_id} = delete $resource->{contract_id};
    $resource->{shared} //= 0;
    return $resource;
}

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    $resource->{contract_id} = delete $resource->{customer_id};

    if ($c->user->roles eq 'subscriberadmin') {
        $resource->{contract_id} = $c->user->account_id;
    }

    return 1;
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    if ($resource->{contract_id}) {
        my $check_rs = $schema->resultset('contracts')->search({
           id => $resource->{contract_id},
        });

        if ($c->user->roles eq 'reseller') {
            $check_rs = $check_rs->search({
               'contact.reseller_id' => $c->user->reseller_id,
            }, {
                join => 'contact',
            });
        }

        unless ($check_rs->first) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id'");
            return;
        }
    }

    unless ($resource->{contract_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required 'customer_id'");
        return;
    }

    my $exists = $schema->resultset('contract_phonebook')->search({
        $item ? (id => { '!=' => $item->id }) : (),
        number => $resource->{number},
        contract_id => $resource->{contract_id},
    })->first;

    if ($exists) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Duplicate entry 'customer_id-number");
        return;
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
