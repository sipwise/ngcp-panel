package NGCP::Panel::Utils::DeviceBootstrap;

use Sipwise::Base;
use NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

sub get_baseuri {
    my ($c) = @_;

    my $uri = 
        ($c->config->{deviceprovisioning}->{secure} ? 'https' : 'http').
        '://'.
        ($c->config->{deviceprovisioning}->{host} // $c->req->uri->host).
        ':'.
        ($c->config->{deviceprovisioning}->{port} // 1444).
        '/device/autoprov/config/';

    return $uri;
}

sub dispatch {
    my ($c, $action, $dev, $old_mac) = @_;

    my $btype = $dev->profile->config->device->bootstrap_method;
    my $mod = 'NGCP::Panel::Utils::DeviceBootstrap';

    if($btype eq 'redirect_panasonic') {
        $mod .= '::Panasonic';
    } elsif($btype eq 'http') {
        return;
    } else {
        return;
    }

    $mod .= '::'.$action;
    $c->log->debug("dispatching bootstrap call to '$mod'");
    no strict "refs";
    return $mod->($c, $dev, $dev->identifier, $old_mac);
}
