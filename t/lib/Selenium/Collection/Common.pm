package Selenium::Collection::Common;

use warnings;
use strict;
use TryCatch;
use Moo;

use Test::More import => [qw(diag ok is)];

extends 'Selenium::Firefox';

# important so that S:F doesn't start an own instance of geckodriver
has '+remote_server_addr' => (
    default => '127.0.0.1',
);

has '+port' => (
    default => '4444',
);

has '+proxy' => (
    default => sub { return {proxyType => 'system'}; },
);

sub BUILD {
    my $self = shift;

    my ($window_h,$window_w) = ($ENV{WINDOW_SIZE} || '1024x1280') =~ /([0-9]+)x([0-9]+)/i;
    my $browsername = $self->browser_name;
    # $self->set_window_position(0, 50) if ($browsername ne "htmlunit");
    # $self->set_window_size($window_h,$window_w) if ($browsername ne "htmlunit");
    # diag("Window size: $window_h x $window_w");
    $self->set_timeout("implicit", 10_000);
}

sub create_domain {
    my ($self, $name) = @_;
    return unless $name;
    diag('Logging in');
    $self->login_ok();

    diag('Go to domains page');
    $self->find_element('//*[@id="main-nav"]/li[5]/a')->click();
    $self->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

    diag('Try to add a domain');
    $self->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
    ok(1, "Domain website seems to exist");
    $self->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
    $self->find_element('//*[@id="domain"]')->send_keys($name);
    $self->find_element('//*[@id="save"]')->click();
    ok(2, "Create field shows and works");
}
1;
