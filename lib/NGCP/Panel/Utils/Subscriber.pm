package NGCP::Panel::Utils::Subscriber;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
use UUID qw/generate unparse/;

my %LOCK = (
    0, 'none',
    1, 'foreign',
    2, 'outgoing',
    3, 'incoming and outgoing',
    4, 'global',
);

sub get_usr_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_subscriber= $params{prov_subscriber};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'usr_pref' => 1,
        })->voip_usr_preferences->search_rs({
            subscriber_id => $prov_subscriber->id,
        });
    return $preference;
}

sub period_as_string {
    my $set = shift;

    my @wdays = (qw/
        invalid Sunday Monday Tuesday Wednesday Thursday Friday Saturday    
    /);
    my @months = (qw/
        invalid January February March April May June July August September October November December
    /);

    my $string = "";
    foreach my $type(qw/year month mday wday hour minute/) {
        my $s = $set->{$type};
        if(defined $s) {
            given($type) {
                when(/^month$/) { 
                    my ($from, $to) = split /\-/, $s;
                    $s = $months[$from];
                    $s .= '-'.$months[$to] if defined($to);
                }
                when(/^wday$/) { 
                    my ($from, $to) = split /\-/, $s;
                    $s = $wdays[$from];
                    $s .= '-'.$wdays[$to] if defined($to);
                }
            }
        }
        $string .= "$type { $s } " if defined($s);
    }
    return $string;
}

sub destination_as_string {
    my $destination = shift;
    my $dest = $destination->{destination};

    if($dest =~ /\@voicebox\.local$/) {
        return "VoiceMail";
    } elsif($dest =~ /\@fax2mail\.local$/) {
        return "Fax2Mail";
    } elsif($dest =~ /\@conference\.local$/) {
        return "Conference";
    } elsif($dest =~ /^sip:callingcard\@app\.local$/) {
        return "CallingCard";
    } elsif($dest =~ /^sip:callthrough\@app\.local$/) {
        return "CallThrough";
    } elsif($dest =~ /^sip:localuser\@.+\.local$/) {
        return "Local Subscriber";
    } else {
        my $d = $dest;
        $d =~ s/sip:(.+)\@.+$/$1/;
        if($d->is_int) {
            return $d;
        } else {
            return $dest;
        }
    }
}

sub lock_provisoning_voip_subscriber {
    my %params = @_;

    my $c = $params{c};
    my $prov_subscriber= $params{prov_subscriber};
    my $level = $params{level};

    return unless $prov_subscriber;

    my $rs = get_usr_preference_rs(
        c => $c, 
        prov_subscriber => $prov_subscriber, 
        attribute => 'lock'
    );
    try {
        if($rs->first) {
            if($level == 0) {
                $rs->first->delete;
            } else {
                $rs->first->update({ value => $level });
            }
        } elsif($level > 0) { # nothing to do for level 0, if no lock is set yet
            $rs->create({ value => $level });
        }
    } catch($e) {
        $c->log->error("failed to set provisioning_voip_subscriber lock: $e");
        $e->rethrow;
    }
}

sub get_lock_string {
    my $level = shift;
    return $LOCK{$level};
}

sub get_admin_subscribers {
    my %params = @_;
    my $subs = $params{voip_subscribers};
    my @subscribers = ();
    foreach my $s(@{ $subs }) {
        push @subscribers, $s if($s->{admin});
    }
    return \@subscribers;
}

sub create_subscriber {
    my %params = @_;
    my $c = $params{c};

    my $contract = $params{contract};
    my $params = $params{params};
    my $administrative = $params{admin_default};
    my $preferences = $params{preferences};

    my $schema = $params{schema} // $c->model('DB');
    my $reseller = $contract->contact->reseller;
    my $billing_domain = $schema->resultset('domains')
            ->find($params->{domain}{id});
    my $prov_domain = $schema->resultset('voip_domains')
            ->find({domain => $billing_domain->domain});
    
    $schema->txn_do(sub {
        my ($uuid_bin, $uuid_string);
        UUID::generate($uuid_bin);
        UUID::unparse($uuid_bin, $uuid_string);

        # TODO: check if we find a reseller and contract and domains

        my ($number, $cli);
        if(defined $params->{e164}{cc} && $params->{e164}{cc} ne '') {
            $cli = $params->{e164}{cc} .
                ($params->{e164}{ac} || '') .
                $params->{e164}{sn};

            $number = $reseller->voip_numbers->create({
                cc => $params->{e164}{cc},
                ac => $params->{e164}{ac} || '',
                sn => $params->{e164}{sn},
                status => 'active',
            });
        }
        my $billing_subscriber = $contract->voip_subscribers->create({
            uuid => $uuid_string,
            username => $params->{username},
            domain_id => $billing_domain->id,
            status => $params->{status},
            primary_number_id => defined $number ? $number->id : undef,
        });
        if(defined $number) {
            $number->update({ subscriber_id => $billing_subscriber->id });
        }

        unless(exists $params->{password}) {
            my ($pass_bin, $pass_str);
            UUID::generate($pass_bin);
            UUID::unparse($pass_bin, $pass_str);
            $params->{password} = $pass_str;
        }
        my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->create({
            uuid => $uuid_string,
            username => $params->{username},
            password => $params->{password},
            webusername => $params->{webusername} || $params->{username},
            webpassword => $params->{webpassword},
            admin => $params->{administrative} // $administrative,
            account_id => $contract->id,
            domain_id => $prov_domain->id,
            is_pbx_group => $params->{is_pbx_group} // 0,
            pbx_group_id => $params->{pbx_group_id},
            create_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        });

        $preferences->{account_id} = $contract->id;
        $preferences->{ac} = $params->{e164}{ac}
            if(defined $params->{e164}{ac} && length($params->{e164}{ac}) > 0);
        $preferences->{cc} = $params->{e164}{cc}
            if(defined $params->{e164}{cc} && length($params->{e164}{cc}) > 0);
        $preferences->{cli} = $cli
            if(defined $cli);

        foreach my $k(keys %{ $preferences } ) {
            my $pref = get_usr_preference_rs(
                c => $c, attribute => $k, prov_subscriber => $prov_subscriber);
            if($pref->first && $pref->first->attribute->max_occur == 1) {
                $pref->first->update({ 
                    'value' => $preferences->{$k},
                });
            } else {
                $pref->create({ 
                    'value' => $preferences->{$k},
                });
            }
        }

        $schema->resultset('voicemail_users')->create({
            customer_id => $uuid_string,
            mailbox => $cli // 0,
            password => sprintf("%04d", int(rand 10000)),
            email => '',
        });
        if($cli) {
            $schema->resultset('dbaliases')->create({
                alias_username => $cli,
                alias_domain => $prov_subscriber->domain->domain,
                username => $prov_subscriber->username,
                domain => $prov_subscriber->domain->domain,
            });
        }

        return $billing_subscriber;
    });
}

1;

=head1 NAME

NGCP::Panel::Utils::Subscriber

=head1 DESCRIPTION

A temporary helper to manipulate subscriber data

=head1 METHODS

=head2 get_usr_preference_rs

Parameters:
    c               The controller
    prov_subscriber The provisioning_voip_subscriber row
    attribute       The name of the usr preference

Returns a result set for the voip_usr_preference of the given subscriber.

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
