package NGCP::Panel::Role::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('packets');

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { message_packets => { message => { voip_subscriber => { contract => 'contact' } } } }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search_rs({
            'contract.id' => $c->user->account_id,
        },{
            join => { message_packets => { message => { voip_subscriber => { contract => 'contact' } } } }
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search_rs({
            'voip_subscriber.uuid' => $c->user->uuid,
        },{
            join => { message_packets => { message => 'voip_subscriber' } }
        });
    }

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return;
}

1;
# vim: set tabstop=4 expandtab:
