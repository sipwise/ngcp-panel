package NGCP::Panel::Controller::API::OTPSecret;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Auth qw();

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    GET => {
        'ReturnContentType' => [ 'image/png', 'text/plain' ],#,
    },    
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
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

    my $item_rs;

    if ($c->user->auth_realm =~ /admin/) {
        $item_rs = $c->model('DB')->resultset('admins')->search({
            -and => [
                id => $c->user->id,
                enable_2fa => 1,
                show_otp_registration_info => 1,
                \[ 'length(`me`.`otp_secret`) > ?', '0' ],
            ]
        },{
        });
    } elsif ($c->user->auth_realm =~ /subscriber/) {
        $item_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            id => $c->user->id,
        },{
        });

        my $show = (NGCP::Panel::Utils::Auth::get_subscriber_enable_2fa($c,$item_rs->first)
            and NGCP::Panel::Utils::Auth::get_subscriber_show_otp_registration_info($c,$item_rs->first) ? 1 : 0);
        
        $item_rs = $item_rs->search({
            -and => [
                \[ '1 = ?', $show ],
            ],
        },{
        });
    }

    return $item_rs;
}

sub return_requested_type {

    my ($self, $c, $id, $item, $return_type) = @_;

    #$c->log->debug("return_requested_type: " . $return_type);

    if ($return_type eq 'text/plain') {
        $c->response->status(200);
        $c->response->content_type($return_type);
        $c->response->body(NGCP::Panel::Utils::Auth::get_otp_secret($c,$item));
        return;
    } elsif ($return_type eq 'image/png') {
        return NGCP::Panel::Role::API::return_requested_type($self, $c, $id, $item, $return_type);
    } else {
        $self->error($c, HTTP_BAD_REQUEST, 'unsupported accept content type');
    }

}

sub get_item_binary_data {

    my($self, $c, $id, $item, $return_type) = @_;

    #$c->log->debug("get_item_binary_data");

    my $data = NGCP::Panel::Utils::Auth::generate_otp_qr($c,$item);

    my $t = time();

    return $data, 'image/png', "qrcode_$t.png"; 

}

1;

