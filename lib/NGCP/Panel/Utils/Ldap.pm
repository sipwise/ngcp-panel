package NGCP::Panel::Utils::Ldap;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(search_dn
                    auth_ldap_simple
                    get_user_dn

                    $ldapconnecterror
                    $ldapnouserdn
                    $ldapauthfailed
                    $ldapsearchfailed
                    $ldapnousersfound
                    $ldapmultipleusersfound
                    $ldapuserfound
                    $ldapauthsuccessful);

use Net::LDAP qw(LDAP_SUCCESS);

our $ldapconnecterror = -1;
our $ldapnouserdn = -2;
our $ldapauthfailed = -3;
our $ldapsearchfailed = -4;
our $ldapnousersfound = -5;
our $ldapmultipleusersfound = -6;
our $ldapuserfound = 1;
our $ldapauthsuccessful = 2;

sub get_user_dn {

    my $c = shift;
    my @args = @_;
    my $user = shift;
    my ($entry, $code, $message) = search_dn($c, $user, @args);
    $user = $entry->dn() if $user;
    my $dn_format = $c->config->{ldap_admin}->{format} ||= '%s';
    return sprintf($dn_format, $user, @args);

}

sub search_dn {

    my ($c,$user_dn, @args) = @_;

    my $message;
    my $label = 'LDAP search: ';

    my $ldap_uri = $c->config->{ldap_admin}->{uri};
    my $ldap_manager_dn = $c->config->{ldap_admin}->{dn};
    my $ldap_manager_password = $c->config->{ldap_admin}->{password};
    my $ldap_manager_search_base = $c->config->{ldap_admin}->{search_base};
    my $ldap_manager_filter_format = $c->config->{ldap_admin}->{filter_format};

    if (length($user_dn)) {
        my $ldap;
        $ldap = Net::LDAP->new($ldap_uri, verify => 'none') if $ldap_uri;
        if (defined $ldap) {
            my $mesg;
            if (length($ldap_manager_dn) > 0) {
                $mesg = $ldap->bind($ldap_manager_dn, password => $ldap_manager_password);
            } else {
                $mesg = $ldap->bind();
            }

            if ($mesg->code() != LDAP_SUCCESS) {
                $message = $mesg->error();
                $c->log->debug($label . $message);
                return (undef, $ldapauthfailed, $message);
            }

            my $search = $ldap->search(base => $ldap_manager_search_base,
                filter => sprintf($ldap_manager_filter_format, $user_dn, @args));

            if ($search->code() != LDAP_SUCCESS) {
                $message = $search->error();
                $c->log->debug($label . $message);
                return (undef, $ldapsearchfailed, $message);
            }

            if ($search->count() == 0) {
                $message = 'no ldap entry found: ' . $user_dn;
                $ldap->unbind();
                $c->log->debug($label . $message);
                return (undef, $ldapnousersfound, $message);
            } elsif ($search->count() > 1) {
                $message = 'multiple ldap entries found: ' . $user_dn;
                $ldap->unbind();
                $c->log->debug($label . $message);
                return (undef, $ldapmultipleusersfound, $message);
            } else {
                my $entry = $search->shift_entry();
                $message = 'ldap entry found: ' . $entry->dn();
                $ldap->unbind();
                $c->log->info($label . $message);

                return ($entry, $ldapuserfound, $message);
            }

        } else {
            $message = $@;
            $c->log->debug($label . $message);
            return (undef, $ldapconnecterror, $message);
        }
    } else {
        $message = 'no user dn specified';
        $c->log->debug($label . $message);
        return (undef, $ldapnouserdn, $message);
    }

}

sub auth_ldap_simple {

    my ($c,$user_dn,$password) = @_;

    my $label = 'LDAP auth: ';

    my $ldap_uri = $c->config->{ldap_admin}->{uri};

    my $message = undef;
    if (length($user_dn) > 0) {
        my $ldap = Net::LDAP->new($ldap_uri, verify => 'none');
        if (defined $ldap) {
            my $mesg = $ldap->bind($user_dn, password => $password);

            if ($mesg->code() != LDAP_SUCCESS) {
                $message = $mesg->error();
                $c->log->debug($label . $message);
                return ($ldapauthfailed,$message);
            } else {
                $message = 'successful ldap authentication: ' . $user_dn;
                $c->log->info($label . $message);
            }

            $ldap->unbind();
            return ($ldapauthsuccessful,$message);
        } else {
            $message = $@;
            $c->log->debug($label . $message);
            return ($ldapconnecterror,$message);
        }
    } else {
        $message = 'no user dn specified';
        $c->log->debug($label . $message);
        return ($ldapnouserdn,$message);
    }

}

1;