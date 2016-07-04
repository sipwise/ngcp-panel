package Selenium::Remote::Driver::Extensions;
use warnings;
use strict;
use Moo;
use Test::More import => [qw(diag ok is)];
use MooseX::Method::Signatures;
use Selenium::Remote::WDKeys;
extends 'Selenium::Remote::Driver';

sub BUILD {
    my $self = shift;

    my ($window_h,$window_w) = ($ENV{WINDOW_SIZE} || '1024x1280') =~ /([0-9]+)x([0-9]+)/i;
    my $browsername = $self->browser_name;
    $self->set_window_position(0, 50) if ($browsername ne "htmlunit");
    $self->set_window_size($window_h,$window_w) if ($browsername ne "htmlunit");
    diag("Window size: $window_h x $window_w");
    $self->set_implicit_wait_timeout(10_000);
    $self->default_finder('xpath');
}

method login_ok() {
    diag("Loading login page (logout first)");
    my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
    $self->get("$uri/logout"); # make sure we are logged out
    $self->get("$uri/login");

    diag("Do Admin Login");
    $self->find_text("Admin Sign In");
    is($self->get_title, '');
    $self->find_element('username', 'name')->send_keys('administrator');
    $self->find_element('password', 'name')->send_keys('administrator');
    $self->find_element('submit', 'name')->click();

    diag("Checking Admin interface");
    is($self->get_title, 'Dashboard');
    is($self->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard");
    ok(1, "Login Successful");
}

method select_if_unselected(Str $query, Str $scheme = "xpath") {
    my $elem = $self->find_element($query, $scheme);
    return 0 unless $elem;
    return 0 unless $elem->is_displayed;
    if (! $elem->is_selected() ) {
        $elem->click;
    }
    return 1;
}

method find_text(Str $text, Str $scheme = "xpath") {
    return $self->find_element("//*[contains(text(),\"$text\")]", $scheme);
}

method fill_element(Str $query, Str $scheme, Str $filltext) {
    my $elem = $self->find_element($query, $scheme);
    return 0 unless $elem;
    return 0 unless $elem->is_displayed;
    #$elem->clear();
    $elem->send_keys(KEYS->{control}, "a"); # select all
    $elem->send_keys($filltext);
    return 1;
}

sub browser_name_in {
    my ($self, @names) = @_;
    my $browser_name = $self->get_capabilities->{browserName};
    return scalar grep {/^$browser_name$/} @names;
}

1;
