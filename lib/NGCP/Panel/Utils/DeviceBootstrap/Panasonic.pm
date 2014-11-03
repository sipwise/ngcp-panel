package NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

use Sipwise::Base;
use URI::Escape;
use MIME::Base64 qw/encode_base64/;
use Net::HTTPS::Any qw/https_post/;
use RPC::XML::ParserFactory 'XML::LibXML';
use RPC::XML;
use Data::Dumper;

my $cfg  = {
    proto    => 'https',
    host     => 'provisioning.e-connecting.net',
    port     => '443',
    path     => '/redirect/xmlrpc',
};

sub prepare {
    my ($c, $fdev) = @_;
    my $p = {};

    my $devmod = $fdev->profile->config->device;
    my $creds = $devmod->autoprov_redirect_credentials;
    if($creds) {
        $p->{auth} = encode_base64($creds->user.':'.$creds->password);
    }

    $p->{uri} = NGCP::Panel::Utils::DeviceBootstrap::get_baseuri($c);
    $p->{uri} .= '{MAC}';
    $p->{uri} = URI::Escape::uri_escape($p->{uri});
    
    return $p;
}

# return faultString or undef if ok
sub check_result {
    my ($c, $data) = @_;
    my $val = '';
    if($data){
        my $parser = RPC::XML::ParserFactory->new();
        my $rpc = $parser->parse($data);
        $val = $rpc->value->value;
    }

    $c->log->debug("panasonic redirect call returned: " . Dumper $val);

    if(ref $val eq 'HASH' && $val->{faultString}) {
        return $val->{faultString};
    } else {
        return;
    }
}

sub normalize_mac {
    my ($mac) = @_;
    return unless($mac);
    $mac =~s/[^A-F0-9]//gi;
    $mac = uc($mac);
    return $mac;
}

sub unregister {
    my ($c, $fdev, $mac, $old_mac) = @_;

    my $p = prepare($c, $fdev);
    $old_mac = normalize_mac($old_mac);

    my $data = "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.unregisterPhone</methodName> 
<params> 
<param><value><string>".$old_mac."</string></value></param> 
</params> 
</methodCall>";

    my($res, $code) = https_post({
        'host'    => $cfg->{host},
        'port'    => $cfg->{port},
        'path'    => $cfg->{path},
        'headers' => { 'Authorization' => 'Basic '.$p->{auth} },
        'Content-Type' => 'text/xml',
        'content' => $data,
    });
    return check_result($c, $res);
}

sub register {
    my ($c, $fdev, $mac, $old_mac) = @_;

    my $p = prepare($c, $fdev);
    $mac = normalize_mac($mac);
    $old_mac = normalize_mac($old_mac);

    # we don't check for the result here, in the worst case
    # we leave an orphaned entry behind
    unregister($c, $fdev, $mac, $old_mac) if($old_mac && $old_mac ne $mac);
    
    my $data = "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.registerPhone</methodName> 
<params> 
<param><value><string>".$mac."</string></value></param> 
<param><value><string>".$p->{uri}."</string></value></param> 
</params> 
</methodCall>";

    my($res, $code) = https_post({
        'host'    => $cfg->{host},
        'port'    => $cfg->{port},
        'path'    => $cfg->{path},
        'headers' => { 'Authorization' => 'Basic '.$p->{auth} },
        'Content-Type' => 'text/xml',
        'content' => $data,
    });
    $c->log->debug("register returned with code $code and data $res"); 
    return check_result($c, $res);
}

1;
# vim: set tabstop=4 expandtab:
