package Selenium::Remote::Driver::FirefoxExtensions;

use warnings;
use strict;
use TryCatch;
use Moo;
use Selenium::Remote::WDKeys;
use Selenium::ActionChains;
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
    $self->set_timeout("implicit", 10_000);
}

sub select_if_unselected {
    my ($self, $query, $scheme) = @_;
    $scheme //= "xpath";
    try {
        my $elem = $self->find_element($query, $scheme);
        if (! $elem->is_selected() ) {
            $elem->click;
        }
        return 1;
    };
    return 0;
}

sub unselect_if_selected {
    my ($self, $query, $scheme) = @_;
    $scheme //= "xpath";
    try {
        my $elem = $self->find_element($query, $scheme);
        if ($elem->is_selected() ) {
            $elem->click;
        }
        return 1;
    };
    return 0;
}

sub fill_element {
    my ($self, $query, $scheme, $filltext) = @_;
    my $elem = $self->find_element($query, $scheme);
    $self->scroll_to_element($elem);
    return 0 unless $elem;
    $elem->send_keys(KEYS->{'control'}, 'A');
    $elem->send_keys($filltext);
    return 1;
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

sub move_and_click {
    my ($self, $path, $type, $fallback, $timeout) = @_;
    return unless $path && $type;
    my $action_chains = Selenium::ActionChains->new(driver => $self);
    $timeout = 20 unless $timeout; # seconds. Default timeout value if none is specified.
    my $started = time();
    my $elapsed = time();
    while ($elapsed - $started <= $timeout){
        $elapsed = time();
        try{
            if($fallback) {
                $action_chains->move_to_element($self->find_element($fallback, $type));
            }
            $action_chains->move_to_element($self->find_element($path, $type));
            $action_chains->click($self->find_element($path, $type));
            $action_chains->perform;
            return 1;
        };
    }
    return 0;
}

sub get_text_safe {
    my ($self, $path, $type) = @_;
    return unless $path;
    $type //= "xpath";
    try {
        my $element = $self->find_element($path, $type);
        return $element->get_text();
    } catch {
        return 'Element not found';
    };
}
1;
