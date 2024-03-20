package NGCP::Panel::Role::API::ResellerPhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

sub resource_name {
    return 'resellerphonebookentries';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('reseller_phonebook');

    if ($c->user->roles eq 'reseller') {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::ResellerAPI", $c);
}

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    if ($c->user->roles eq 'reseller') {
        $resource->{reseller_id} = $c->user->reseller_id;
    }

    return 1;
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    if ($resource->{reseller_id}) {
        my $check_rs = $schema->resultset('resellers')->search({
           id => $resource->{reseller_id},
        });

        unless ($check_rs->first) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }

    unless ($resource->{reseller_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required 'reseller_id'");
        return;
    }

    my $exists = $schema->resultset('reseller_phonebook')->search({
        $item ? (id => { '!=' => $item->id }) : (),
        number => $resource->{number},
        reseller_id => $resource->{reseller_id},
    })->first;

    if ($exists) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Duplicate entry 'reseller_id-number");
        return;
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
