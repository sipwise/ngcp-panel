package Selenium::Remote::Driver::FirefoxExtensions;

use warnings;
use strict;
use TryCatch;
use Moo;
use Selenium::Remote::WDKeys;
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

sub find_text {
    try {
        my ($self, $text, $scheme) = @_;
        $scheme //= "xpath";
        return $self->find_element("//*[contains(text(),\"$text\")]", $scheme);
    }
    catch {
        return;
    };

}

sub select_if_unselected {
    my ($self, $query, $scheme) = @_;
    $scheme //= "xpath";
    my $elem = $self->find_element($query, $scheme);
    return 0 unless $elem;
    return 0 unless $elem->is_displayed;
    if (! $elem->is_selected() ) {
        $elem->click;
    }
    return 1;
}

sub fill_element {
    my ($self, $query, $scheme, $filltext) = @_;
    my $elem = $self->find_element($query, $scheme);
    return 0 unless $elem;
    return 0 unless $elem->is_displayed;
    $elem->send_keys(KEYS->{'control'}, 'A');
    $elem->send_keys($filltext);
    return 1;
}

sub scroll_to_id {
    my ($self, $id) = @_;
       my $script =
       'var arg1 = arguments[0];' .
       'var elem = window.document.getElementById(arg1);' .
       'elem.scrollIntoView();' .
       'return elem;';
   my $elem = $self->execute_script($script,$id);
   return $elem;
}

sub scroll_to_element {
    my ($self, $elem) = @_;
       my $script =
       'var arg1 = arguments[0];' .
       'arg1.scrollIntoView();' .
       'return arg1;';
   $self->execute_script($script,$elem);
   return $elem;
}

sub browser_name_in {
    my ($self, @names) = @_;
    my $browser_name = $self->browser_name;
    return scalar grep {/^$browser_name$/} @names;
}

sub wait_for_text {
    my ($self, $xpath, $expected, $timeout) = @_;
    return unless $xpath && $expected;
    $timeout = 5 unless $timeout; # seconds. Default timeout value if none is specified.
    my $started = time();
    my $elapsed = time();
    while ($elapsed - $started <= $timeout){
        $elapsed = time();
        try{
            return 1 if $self->find_element($xpath)->get_text() eq $expected;
        };
    }
    return;
}

sub move_and_click {
    my ($self, $path, $type, $timeout) = @_;
    return unless $path && $type;
    $timeout = 5 unless $timeout; # seconds. Default timeout value if none is specified.
    my $started = time();
    my $elapsed = time();
    while ($elapsed - $started <= $timeout){
        $elapsed = time();
        try{
            $self->move_action(element => $self->find_element($path, $type));
            $self->find_element($path, $type)->click();
            return 1;
        };
    }
    return;
}
1;
