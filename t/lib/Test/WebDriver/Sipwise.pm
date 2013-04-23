package Test::WebDriver::Sipwise;
use Sipwise::Base;
extends 'Test::WebDriver';

method find(Str $scheme, Str $query) {
    $self->find_element($query, $scheme);
}

method findclick(Str $scheme, Str $query) {
    my $elem = $self->find($scheme, $query);
    return 0 unless $elem;
    $elem->click;
    return 1;
}

method findtext(Str $text, Any $ignore) {
    return $self->find(xpath => "//*[contains(text(),\"$text\")]");
}
