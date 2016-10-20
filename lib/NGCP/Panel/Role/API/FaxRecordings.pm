package NGCP::Panel::Role::API::FaxRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_fax_journal')->search({
        filename => { '!=' => '' },
        'voip_subscriber.id' => { '!=' => undef },
    },{
        join => { 'provisioning_voip_subscriber' => 'voip_subscriber' },
    });

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } }
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
