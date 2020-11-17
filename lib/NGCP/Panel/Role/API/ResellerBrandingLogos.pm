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
    my $item_rs;
    if ($c->req->param('subscriber_id')) {
        $item_rs = $c->model('DB')->resultset('resellers')->search(
            {
                'voip_subscribers.id' => $c->req->param('subscriber_id')
            },
            {
                join => { 'contacts' => { 'contracts' => 'voip_subscribers' } }
            }
        );
    } else {
        $item_rs = $c->model('DB')->resultset('resellers')->search({
            status => { '!=' => 'terminated' }
        });
    }
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        my $reseller_id = $c->user->contract->contact->reseller_id;
        return unless $reseller_id;
        $item_rs = $item_rs->search({
            reseller_id => $reseller_id,
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
