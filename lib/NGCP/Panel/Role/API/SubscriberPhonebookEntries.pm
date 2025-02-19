package NGCP::Panel::Role::API::SubscriberPhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

sub resource_name {
    return 'subscriberphonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $params = $c->req->params;

    my $item_rs = $c->model('DB')->resultset('subscriber_phonebook');

    if ($c->req->method eq 'GET' && $params->{include}) {
        if ($params->{include} eq 'all') {
            $item_rs = $c->model('DB')->resultset('v_subscriber_phonebook');
        } elsif ($params->{include} eq 'reseller') {
            $item_rs = $c->model('DB')->resultset('v_subscriber_reseller_phonebook');
        } elsif ($params->{include} eq 'customer') {
            $item_rs = $c->model('DB')->resultset('v_subscriber_contract_phonebook');
        }
    }

    if ($c->user->roles eq 'reseller' || $c->user->roles eq 'ccare') {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { subscriber => { contract => 'contact' } },
        });
    } elsif ($c->user->roles eq 'subscriberadmin') {
        $item_rs = $item_rs->search({
            'subscriber.contract_id' => $c->user->account_id,
        },{
            join => 'subscriber',
        });
    } elsif ($c->user->roles eq 'subscriber') {
        $item_rs = $item_rs->search({
            'subscriber_id' => $c->user->voip_subscriber->id,
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

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::SubscriberAPI", $c);
}

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    if ($c->user->roles eq 'subscriber') {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    }

    return 1;
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    if ($resource->{subscriber_id}) {
        my $check_rs = $schema->resultset('voip_subscribers')->search({
           id => $resource->{subscriber_id},
        });

        if ($c->user->roles eq 'reseller') {
            $check_rs = $check_rs->search({
               'contact.reseller_id' => $c->user->reseller_id,
            }, {
                join => { contract => 'contact' },
            });
        } elsif ($c->user->roles eq 'subscriberadmin') {
            $check_rs = $check_rs->search({
               'contract_id' => $c->user->account_id,
            });
        }

        unless ($check_rs->first) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'");
            return;
        }
    } else {
        if ($c->user->roles eq 'subscriberadmin') {
            $resource->{subscriber_id} = $c->user->voip_subscriber->id;
        }
    }

    unless ($resource->{subscriber_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required 'subscriber_id'");
        return;
    }

    my $exists = $schema->resultset('subscriber_phonebook')->search({
        $item ? (id => { '!=' => $item->id }) : (),
        number => $resource->{number},
        subscriber_id => $resource->{subscriber_id},
    })->first;

    if ($exists) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Duplicate entry 'subscriber_id-number");
        return;
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
