package NGCP::Panel::Utils::Voucher;
use Sipwise::Base;
use Crypt::Rijndael;
use MIME::Base64;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();

sub encrypt_code {
    my ($c, $plain) = @_;

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
    my $encrypted = $cipher->encrypt($plain);
    my $b64 = encode_base64($encrypted, '');
    return $b64;
}

sub decrypt_code {
    my ($c, $code) = @_;

    my $key = $c->config->{vouchers}->{key};
    my $iv = $c->config->{vouchers}->{iv};

    my $cipher = Crypt::Rijndael->new(
        $key,
        Crypt::Rijndael::MODE_CBC()
    );
    $cipher->set_iv($iv);
    my $encrypted = decode_base64($code);
    my $plain = $cipher->decrypt($encrypted) . "";
    # remove padding
    $plain =~ s/[\x01-\x1e]*$//;
    return $plain;
}

sub check_topup {
    my %params = @_;
    my ($c,$plain_code,$voucher_id,$now,$subscriber_id,$contract_id,$contract,$package_id,$schema,$err_code,$entities,$resource) = @params{qw/c plain_code voucher_id now subscriber_id contract_id contract package_id schema err_code entities resource/};

    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $reseller_id;
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    if (defined $subscriber_id) {
        my $subscriber = $schema->resultset('voip_subscribers')->find($subscriber_id);
        unless($subscriber) {
            if (defined $resource) {
                $resource->{subscriber_id} = undef if exists $resource->{subscriber_id};
                $resource->{subscriber}->{id} = undef if (exists $resource->{subscriber} && exists $resource->{subscriber}->{id});
            }
            return 0 unless &{$err_code}("Unknown subscriber ID $subscriber_id.");
        }
        $entities->{subscriber} = $subscriber if defined $entities;
        $contract //= $subscriber->contract;
    } elsif (defined $contract_id) {
        $contract = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c)->find($contract_id) unless $contract;
        unless($contract) {
            if (defined $resource) {
                $resource->{contract_id} = undef if exists $resource->{contract_id};
                $resource->{contract}->{id} = undef if (exists $resource->{contract} && exists $resource->{contract}->{id});
            }
            return 0 unless &{$err_code}("Unknown contract ID $contract_id.");
        }
    }

    $entities->{contract} = $contract if defined $entities;

    unless($contract->status eq 'active') {
        return 0 unless &{$err_code}('Customer contract is not active.');
    }
    unless($contract->contact->reseller) {
        return 0 unless &{$err_code}('Contract is not a customer contract.');
    }

    # if reseller, check if subscriber_id belongs to the calling reseller
    if($reseller_id && $reseller_id != $contract->contact->reseller_id) {
        return 0 unless &{$err_code}('Subscriber customer contract belongs to another reseller.');
    }

    if (defined $plain_code || defined $voucher_id) {

        my $voucher;
        my $dtf = $schema->storage->datetime_parser;

        if (defined $plain_code) {
            $voucher = $schema->resultset('vouchers')->search_rs({
                code => encrypt_code($c, $plain_code),
                used_at => { '=' => \"'0000-00-00 00:00:00'" } , #used_by_subscriber_id => undef,
                valid_until => { '>=' => $dtf->format_datetime($now) },
                reseller_id => $contract->contact->reseller_id,
            },{
                for => 'update',
            })->first;
            unless($voucher) {
                if (defined $resource) {
                    $resource->{voucher_id} = undef if exists $resource->{voucher_id};
                    $resource->{voucher}->{id} = undef if (exists $resource->{voucher} && exists $resource->{voucher}->{id});
                }
                return 0 unless &{$err_code}("Invalid voucher code '$plain_code', already used or expired.");
            }
        } else {
            $voucher = $schema->resultset('vouchers')->search_rs({
                id => $voucher_id,
                used_at => { '=' => \"'0000-00-00 00:00:00'" }, #used_by_subscriber_id => undef,
                valid_until => { '>=' => $dtf->format_datetime($now) },
                reseller_id => $contract->contact->reseller_id,
            },{
                for => 'update',
            })->first;
            unless($voucher) {
                if (defined $resource) {
                    $resource->{voucher_id} = undef if exists $resource->{voucher_id};
                    $resource->{voucher}->{id} = undef if (exists $resource->{voucher} && exists $resource->{voucher}->{id});
                }
                return 0 unless &{$err_code}("Invalid voucher ID $voucher_id, already used or expired.");
            }
        }

        $entities->{voucher} = $voucher if defined $entities;

        if($voucher->customer_id && $contract->id != $voucher->customer_id) {
            return 0 unless &{$err_code}('Voucher is reserved for a different customer.');
        }
        unless($voucher->reseller_id == $contract->contact->reseller_id) {
            return 0 unless &{$err_code}('Voucher belongs to another reseller.');
        }

    } else {
        my $package = undef;
        if (defined $package_id) {
            $package = $schema->resultset('profile_packages')->find($package_id);
            unless($package) {
                if (defined $resource) {
                    $resource->{package_id} = undef if exists $resource->{package_id};
                    $resource->{package}->{id} = undef if (exists $resource->{package} && exists $resource->{package}->{id});
                }
                return 0 unless &{$err_code}("Unknown profile package ID $package_id.");
            }
            $entities->{package} = $package if defined $entities;
            if ($package->reseller_id && $package->reseller_id != $contract->contact->reseller_id) {
                return 0 unless &{$err_code}('Profile package belongs to another reseller.');
            }
        }
    }

    # TODO: add and check billing.vouchers.active flag for internal/emergency use

    return 1;

}

sub get_datatable_cols {

    my ($c,$hide_package) = @_;
    return (
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        $c->user->billing_data ? { name => "code", "search" => 1, "title" => $c->loc("Code") } : (),
        { name => "amount", "search" => 1, "title" => $c->loc("Amount") },
        { name => "reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
        $hide_package ? () : { name => "profile_package.name", "search" => 1, "title" => $c->loc("Profile Package") },
        #{ name => "customer_contact_email", "search" => 1, "title" => $c->loc("Reserved for Customer") },
        { name => "customer_id", "search" => 1, "title" => $c->loc("For Contract #") },
        { name => "valid_until", "search" => 1, "title" => $c->loc("Valid Until") },
        { name => "used_at", "search" => 1, "title" => $c->loc("Used At") },
        { name => "used_by_subscriber.id", "search" => 1, "title" => $c->loc("Used By Subscriber #") },
    );
}

1;
