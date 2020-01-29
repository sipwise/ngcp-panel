package NGCP::Panel::Controller::Security;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Security;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub base :Chained('/') :PathPart('security') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{bannedips_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "ip", search => 1, title => $c->loc("IP") },
    ]);

    $c->stash->{bannedusers_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "username", search => 1, title => $c->loc("User") },
        { name => "auth_count", title => $c->loc("Fail Count") },
        { name => "last_auth", search => 1, title => $c->loc("Last Attempt") },
    ]);
    $c->stash(
        template => 'security/list.tt',
    );
}

sub security :Chained('base') :PathPart('') :Args(0) {
}

sub ip_list :Chained('base') :PathPart('ip') :Args(0) {
    my ($self, $c) = @_;
    my $ips = NGCP::Panel::Utils::Security::list_banned_ips($c);

    NGCP::Panel::Utils::Datatables::process_static_data($c, $ips, $c->stash->{bannedips_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub user_list :Chained('base') :PathPart('user') :Args(0) {
    my ($self, $c) = @_;
    my $users = NGCP::Panel::Utils::Security::list_banned_users($c);

    NGCP::Panel::Utils::Datatables::process_static_data($c, $users, $c->stash->{bannedusers_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub ip_base :Chained('/') :PathPart('security/ip') :CaptureArgs(1) {
    my ( $self, $c, $ip ) = @_;
    my $decoder = URI::Encode->new;
    $c->stash->{ip} = $decoder->decode($ip);
}

sub ip_unban :Chained('ip_base') :PathPart('unban') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->user->read_only) {
        $c->detach('/denied_page');
    }

    my $ip = $c->stash->{ip};
    NGCP::Panel::Utils::Security::ip_unban($c, $ip);
    NGCP::Panel::Utils::Message::info(
        c    => $c,
        data => { ip => $ip },
        desc => $c->loc('IP successfully unbanned'),
    );
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/security'));
}

sub user_base :Chained('/') :PathPart('security/user') :CaptureArgs(1) {
    my ( $self, $c, $user ) = @_;
    my $decoder = URI::Encode->new;
    $c->stash->{user} = $decoder->decode($user);
}

sub user_unban :Chained('user_base') :PathPart('unban') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->user->read_only) {
        $c->detach('/denied_page');
    }

    my $user = $c->stash->{user};
    NGCP::Panel::Utils::Security::user_unban($c, $user);
    NGCP::Panel::Utils::Message::info(
        c    => $c,
        data => { user => $user },
        desc => $c->loc('User successfully unbanned'),
    );
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/security'));
}


1;

# vim: set tabstop=4 expandtab:
