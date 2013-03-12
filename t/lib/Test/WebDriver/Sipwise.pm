package Test::WebDriver::Sipwise;
use Sipwise::Base;
extends 'Test::WebDriver';

method find(Str $scheme, Str $query) {
    $self->find_element($query, $scheme);
}
