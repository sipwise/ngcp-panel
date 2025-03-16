package NGCP::Panel::Controller::API::OTPSecret;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Auth qw();

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

    my $data = NGCP::Panel::Utils::Auth::generate_otp_qr($c,$item);

    my $t = time();

    return $data, 'image/png', "qrcode_$t.png"; 

}

1;

