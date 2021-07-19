package NGCP::Panel::Controller::Statistics;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Statistics;
use NGCP::Panel::Utils::Navigation;

use Sys::Hostname;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub statistics_index :Chained('/') :PathPart('statistics') :Args(0) {
    my ( $self, $c ) = @_;
    my $versions_info = NGCP::Panel::Utils::Statistics::get_dpkg_versions();
    $c->stash(versions_info => $versions_info,
        template => 'statistics/versions.tt',
    );
    return;
}

sub versions :Chained('/') :PathPart('statistics/versions') :Args() {
    my ( $self, $c ) = @_;
    my $versions_info = NGCP::Panel::Utils::Statistics::get_dpkg_versions();
    $c->stash(versions_info => $versions_info,
        #template => 'statistics/versions.tt',
    );
    return;
}

sub supportstatus :Chained('/') :PathPart('statistics/supportstatus') :Args() {
    my ( $self, $c ) = @_;
    my $support_status_code = NGCP::Panel::Utils::Statistics::get_dpkg_support_status();
    if ($support_status_code == 3) {
        $c->log->warn("Couldn't properly determine support status");
    }
    $c->stash(support_status_code => $support_status_code,
        #template => 'statistics/supportstatus.tt',
    );

    if (!$c->stash->{openvpn_info}) {
        my $openvpn_info = NGCP::Panel::Utils::Auth::check_openvpn_status($c);
        $c->stash(openvpn_info => $openvpn_info);
    }

    return;
}


1;

__END__

=head1 NAME

NGCP::Panel::Controller::Statistics

=head1 DESCRIPTION

A controller to manipulate the statistics data

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
