package NGCP::Panel::Controller::API::OTPSecret;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API/;

use Sipwise::Base;
use Imager::QRCode qw();
use URI::Encode qw(uri_encode);

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    GET => {
        'ReturnContentType' => ['image/png'],#,
    },    
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub item_name {
    return 'otpsecret';
}

sub resource_name {
    return 'otpsecret';
}

sub item_by_id_valid {
    my ($self, $c) = @_;
    my $item_rs = $self->item_rs($c);
    my $item = $item_rs->first;
    $self->error($c, HTTP_BAD_REQUEST, "no OTP") unless $item;
    return $item;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $where;
    my $item_rs = $c->model('DB')->resultset('admins')->search({
        -and => [
            id => $c->user->id,
            enable_2fa => 1,
            show_otp_registration_info => 1,
            \[ 'length(`me`.`otp_secret`) > ?', '0' ],
        ]
    },{
        #'+select' => { '' => \[ 'length(`me`.`otp_secret`)' ], -as => 'otp_secret_length' },
        #select => [ { length => 'otp_secret' } ],
        #s => [ 'otp_secret_length' ],
    });

    return $item_rs;
}

sub get_item_binary_data{

    my($self, $c, $id, $item, $return_type) = @_;

    #<img src="$http_base_url/chart?chs=150x150&chld=M%7c0&cht=qr&chl=otpauth://totp/$string_utils.urlEncode($inheriteduser_name,$template_encoding)@$string_utils.urlEncode($instance_name,$template_encoding)?secret=$otp_secret"/>
    my $qrcode = Imager::QRCode->new(
        size          => 4,
        margin        => 3,
        version       => 1,
        level         => 'M',
        casesensitive => 1,
        lightcolor    => Imager::Color->new(255, 255, 255),
        darkcolor     => Imager::Color->new(0, 0, 0),
    );
    
    my $image = $qrcode->plot(sprintf("otpauth://totp/%s@%s?secret=%s&issuer=%s",
        uri_encode($item->login),
        uri_encode($c->req->uri->host),
        $item->otp_secret,
        'NGCP', # . $c->config->{ngcp_version}
    ));

    my $data;
    $image->write(data => \$data, type => 'png')
        or die $image->errstr;

    my $t = time();

    return \$data, 'image/png', "qrcode_$t.png";

}

1;

