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
    my $dn_format = $c->config->{ldap_admin}->{format};
    $dn_format ||= '%s';
    print sprintf($dn_format, @_);
    return sprintf($dn_format, @_);
}

sub search_dn {

    my ($c,$user_dn) = @_;

    my $message;
    my $label = 'LDAP search: ';

    my $ldap_uri = $c->config->{ldap_admin}->{uri};
    my $ldap_manager_dn = $c->config->{ldap_admin}->{dn};
    my $ldap_manager_password = $c->config->{ldap_admin}->{password};

    if (length($user_dn)) {
        my $ldap = Net::LDAP->new($ldap_uri, verify => 'none');
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
                return ($ldapauthfailed, $message);
            }

            my $search = $ldap->search(base => $user_dn, scope => 'base', filter => '(objectClass=*)'); #attrs => ['dn'], );

            if ($search->code() != LDAP_SUCCESS) {
                $message = $search->error();
                $c->log->debug($label . $message);
                return ($ldapsearchfailed,$message);
            }

            if ($search->count() == 0) {
                $message = 'no ldap entry found: ' . $user_dn;
                $ldap->unbind();
                $c->log->debug($label . $message);
                return ($ldapnousersfound,$message);
            } elsif ($search->count() > 1) {
                $message = 'multiple ldap entries found: ' . $user_dn;
                $ldap->unbind();
                $c->log->debug($label . $message);
                return ($ldapmultipleusersfound,$message);
            } else {
                my $entry = $search->shift_entry();
                $message = 'ldap entry found: ' . $entry->dn();
                $ldap->unbind();
                $c->log->info($label . $message);

                return ($ldapuserfound,$message);
            }

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


sub auth_ldap_simple {

    my ($c,$user_dn,$password) = @_;

    my $label = 'LDAP auth: ';

    my $ldap_uri = $c->config->{ldap}->{admins}->{uri};

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