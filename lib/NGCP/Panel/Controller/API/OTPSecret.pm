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
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub item_name {
    return 'otpsecret';
}

sub resource_name {
    return 'otpsecret';
}

sub query_params {
    return [
        {
            param => 'admin_id',
            description => 'OTP secret of given admin',
            query => undef, #dummy param
        },
        {
            param => 'subscriber_id',
            description => 'OTP secret of given billing subscriber id',
            query => undef, #dummy param
        },
    ];
}

sub item_by_id_valid {

    my ($self, $c) = @_;
    my $item_rs = $self->item_rs($c);
    my $item;
    $item = $item_rs->first if $item_rs;
    $self->error($c, HTTP_BAD_REQUEST, "no OTP") unless $item;
    return $item;

}

sub _get_admin {
    my ($c,$id,$show) = @_;
    my $item_rs = $c->model('DB')->resultset('admins')->search({
        -and => [
            id => $id,
            enable_2fa => 1,
            ($show ? (show_otp_registration_info => 1) : ()),
            \[ 'length(`me`.`otp_secret`) > ?', '0' ],
        ]
    },{
    });

    #my ($stmt, @bind_vals) = @{${$item_rs->as_query}};
    #@bind_vals = map { $_->[1]; } @bind_vals;
    #$c->log->debug("otp query stmt: " . $stmt);
    #$c->log->debug("otp query stmt bind: " . join(",",@bind_vals));

    return $item_rs;
}

sub _get_subscriber {
    my ($c,$id,$show) = @_;
    my $item_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
        id => $id,
    },{
    });

    $show = (NGCP::Panel::Utils::Auth::get_subscriber_enable_2fa($c,$item_rs->first)
        and ((not $show) or NGCP::Panel::Utils::Auth::get_subscriber_show_otp_registration_info($c,$item_rs->first)) ? 1 : 0);

    $item_rs = $item_rs->search({
        -and => [
            \[ '1 = ?', $show ],
        ],
    },{
    });

    #my ($stmt, @bind_vals) = @{${$item_rs->as_query}};
    #@bind_vals = map { $_->[1]; } @bind_vals;
    #$c->log->debug("otp query stmt: " . $stmt);
    #$c->log->debug("otp query stmt bind: " . join(",",@bind_vals));

    return $item_rs;
}

sub _item_rs {
    my ($self, $c, $delete) = @_;

    my $item_rs;

    if ($c->user->auth_realm =~ /admin/) {
        if ($c->request->params->{admin_id}) {
            if ($c->user->is_master and grep { $c->user->roles eq $_; } qw(admin reseller)) {
                $item_rs = _get_admin($c,$c->request->params->{admin_id},not $delete);
                $item_rs = $item_rs->search_rs({
                    reseller_id => $c->user->reseller_id,
                },{

                }) if grep { $c->user->roles eq $_; } qw(reseller);
            } else {
                $self->error($c, HTTP_FORBIDDEN, "insufficient privileges for OTP of this admin");
            }
        } elsif ($c->request->params->{subscriber_id}) {
            if (grep { $c->user->roles eq $_; } qw(admin reseller ccareadmin ccare)) {
                my $bs = $c->model('DB')->resultset('voip_subscribers')->search_rs({
                    id => $c->request->params->{subscriber_id},
                },{
                });
                $bs = $bs->search_rs({
                    'contact.reseller_id' => $c->user->reseller_id,
                }, {
                    join => { 'contract' => 'contact' },
                }) if grep { $c->user->roles eq $_; } qw(reseller ccare);
                $bs = $bs->first;
                last unless $bs;
                my $ps = $bs->provisioning_voip_subscriber;
                last unless $ps;
                $item_rs = _get_subscriber($c,$ps->id,not $delete);
            } else {
                $self->error($c, HTTP_FORBIDDEN, "insufficient privileges for OTP of this subscriber");
            }
        } else {
            if ($delete) {
                if (grep { $c->user->roles eq $_; } qw(admin reseller)) {
                    $item_rs = _get_admin($c,$c->user->id,0);
                } else {
                    $self->error($c, HTTP_FORBIDDEN, "insufficient privileges to clear own OTP");
                }
            } else {
                $item_rs = _get_admin($c,$c->user->id,1);
            }
        }
    } elsif ($c->user->auth_realm =~ /subscriber/) {
        if ($c->request->params->{admin_id}) {
            $self->error($c, HTTP_FORBIDDEN, "insufficient privileges for OTP of this admin");
        } elsif ($c->request->params->{subscriber_id}) {
            if (grep { $c->user->roles eq $_; } qw(subscriberadmin)) {
                my $bs = $c->model('DB')->resultset('voip_subscribers')->search({
                    id => $c->request->params->{subscriber_id},
                    'contract_id' => $c->user->contract->id,
                },{
                })->first;
                my $ps = $bs->provisioning_voip_subscriber;
                last unless $ps;
                $item_rs = _get_subscriber($c,$ps->id,not $delete);
            } else {
                $self->error($c, HTTP_FORBIDDEN, "insufficient privileges for OTP of this subscriber");
            }
        } else {
            if ($delete) {
                #if (grep { $c->user->roles eq $_; } qw(subscriberadmin)) {
                #    $item_rs = _get_subscriber($c,$c->user->id,0);
                #} else {
                    $self->error($c, HTTP_FORBIDDEN, "insufficient privileges to clear own OTP");
                #}
            } else {
                $item_rs = _get_subscriber($c,$c->user->id,1);
            }
        }
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

sub DELETE :Allow {
    my ($self, $c) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $user = $self->_item_rs($c, 1)->first;
        last unless $self->resource_exists($c, user => $user);

        try {
            NGCP::Panel::Utils::Auth::clear_otp_secret($c,$user);
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                         "Failed to clear OTP", $e);
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

