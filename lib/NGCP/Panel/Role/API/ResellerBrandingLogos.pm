package NGCP::Panel::Role::API::ResellerBrandingLogos;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

sub resource_name{
    return 'resellerbrandinglogos';
}
sub dispatch_path{
    return '/api/resellerbrandinglogos/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-resellerbrandinglogos';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('reseller_brandings')->search({
        'reseller.status' => { '!=' => 'terminated' }
    },{
        join => 'reseller'
    });

    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'me.reseller_id' => $c->user->reseller_id
        });
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            'provisioning_voip_subscriber.id' => $c->user->id,
        },{
            join => { 'reseller' => {
                        'contacts' => {
                            'contracts' => {
                                'voip_subscribers' => 'provisioning_voip_subscriber'
                            }
                        }
                    }
            }
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
