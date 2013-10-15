package NGCP::Panel::ValidateJSON;
use Sipwise::Base;
extends 'JSON::Tiny::Subclassable';

my $WHITESPACE_RE = qr/[\x20\x09\x0a\x0d]*/;

sub new {
    my ($self, $json) = @_;
    $self = $self->next::method;
    $self->decode($json);
    die $self->error . "\n" if $self->error;
}

sub _decode_object {
    my $self = shift;
    my $hash = $self->_new_hash;
    until (m/\G$WHITESPACE_RE\}/gc) {
        m/\G$WHITESPACE_RE"/gc or $self->_exception('Expected string while parsing object');
        my $key = $self->_decode_string;
        $self->_exception("Unexpected duplicate object member name $key") if exists $hash->{$key};
        m/\G$WHITESPACE_RE:/gc or $self->_exception('Expected colon while parsing object');
        $hash->{$key} = $self->_decode_value;
        redo if m/\G$WHITESPACE_RE,/gc;
        last if m/\G$WHITESPACE_RE\}/gc;
        $self->_exception('Expected comma or right curly bracket while parsing object');
    }
    return $hash;
}
