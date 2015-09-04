package Selenium::Remote::Driver::Extensions;
use warnings;
use strict;
use Moo;
use MooseX::Method::Signatures;
extends 'Selenium::Remote::Driver';

method init_browser_setup() {
  my $browsername = $ENV{BROWSER_NAME} || "firefox";
  $self->set_window_position(0, 50) if ($browsername ne "htmlunit");
  $self->set_window_size(1024,1280) if ($browsername ne "htmlunit");

  $self->default_finder('xpath');
  $self->set_implicit_wait_timeout(10000);

  my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
  $self->get("$uri/logout"); # make sure we are logged out
  $self->get("$uri/login");
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

method save_screenshot() {
    use MIME::Base64;
    open(my $FH,'>','screenshot.png');
    binmode $FH;
    my $png_base64 = $self->screenshot();
    print $FH decode_base64($png_base64);
    close $FH;
}

method fill_element(Str $query, Str $scheme, Str $filltext) {
    my $elem = $self->find_element($query, $scheme);
    return 0 unless $elem;
    return 0 unless $elem->is_displayed;
    $elem->clear();
    $elem->send_keys($filltext);
    return 1;
}

sub browser_name_in {
    my ($self, @names) = @_;
    my $browser_name = $self->get_capabilities->{browserName};
    return scalar grep {/^$browser_name$/} @names;
}

1;
