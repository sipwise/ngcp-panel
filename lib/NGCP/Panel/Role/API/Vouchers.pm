package NGCP::Panel::Role::API::Vouchers;
use Moose::Role;
use Sipwise::Base;
use Crypt::Rijndael;
use MIME::Base64;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Voucher::AdminAPI;
use NGCP::Panel::Form::Voucher::ResellerAPI;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('vouchers');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::Voucher::AdminAPI->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::Voucher::ResellerAPI->new;
    }
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{valid_until} = $item->valid_until->ymd('-') . ' ' . $item->valid_until->hms(':');
    $resource{code} = $self->decrypt_code($c, $item->code);
    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub encrypt_code {
    my ($self, $c, $plain) = @_;

    my $key = $c->config->{vouchers}->{key};
    my $iv = $c->config->{vouchers}->{iv};

    # pkcs#5 padding to 16 bytes blocksize
    my $pad = 16 - (length $plain) % 16;
    $plain .= pack('C', $pad) x $pad;

    my $cipher = Crypt::Rijndael->new(
        $key,
        Crypt::Rijndael::MODE_CBC()
    );
    $cipher->set_iv($iv);
    my $crypted = $cipher->encrypt($plain);
    my $b64 = encode_base64($crypted, '');
    return $b64;
}

sub decrypt_code {
    my ($self, $c, $code) = @_;

    my $key = $c->config->{vouchers}->{key};
    my $iv = $c->config->{vouchers}->{iv};

    my $cipher = Crypt::Rijndael->new(
        $key,
        Crypt::Rijndael::MODE_CBC()
    );
    $cipher->set_iv($iv);
    my $crypted = decode_base64($code);
    my $plain = $cipher->decrypt($crypted) . "";
    # remove padding
    $plain =~ s/[\x01-\x1e]*$//;
    return $plain;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    }

    my $code = $self->encrypt_code($c, $resource->{code});
    my $dup_item = $c->model('DB')->resultset('vouchers')->find({
        reseller_id => $resource->{reseller_id},
        code => $code,
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("voucher with code '$$resource{code}' already exists for reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Voucher with this code already exists for this reseller");
        return;
    }
    $resource->{code} = $code;

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
