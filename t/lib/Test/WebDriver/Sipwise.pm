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

method save_screenshot() {
    use MIME::Base64;
    local *FH;
    open(FH,'>','screenshot.png');
    binmode FH;
    my $png_base64 = $self->screenshot();
    print FH decode_base64($png_base64);
    close FH;
}
