package NGCP::Panel::Role::API::CustomerPhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

sub resource_name {
    return 'customerphonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('contract_phonebook');

    if ($c->user->roles eq 'reseller') {
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

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::CustomerAPI", $c);
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{customer_id} = delete $resource->{contract_id};
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
            $c->log->error("Invalid 'customer_id'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id'");
            return;
        }
    }

    unless ($resource->{contract_id}) {
        $c->log->error("Required 'customer_id'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required 'customer_id'");
        return;
    }

    my $exists = $schema->resultset('contract_phonebook')->search({
        $item ? (id => { '!=' => $item->id }) : (),
        number => $resource->{number},
        contract_id => $resource->{contract_id},
    })->first;

    if ($exists) {
        $c->log->error("Duplicate entry 'customer_id-number");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Duplicate entry 'customer_id-number");
        return;
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
