package NGCP::Panel::Middleware::TEgzip;
use Sipwise::Base;
use HTTP::Headers::Util qw(split_header_words);
use Plack::Middleware::Deflater;
# for internal package Plack::Middleware::Deflater::Encoder
use Plack::Util qw();
extends 'Plack::Middleware';

sub call {
    my ($self, $env) = @_;
    my $res = $self->app->($env);
    if (
        defined $env->{HTTP_TE}
        && grep {
            my %coding = @{$_};
               exists $coding{gzip} && !exists $coding{'q'}
            || exists $coding{gzip} &&  exists $coding{'q'} && $coding{'q'}->is_positive
        } split_header_words $env->{HTTP_TE}
    ) {
        $self->response_cb($res, sub {
            my $res = shift;
            my $h = Plack::Util::headers($res->[1]);
            if (
                $env->{'SERVER_PROTOCOL'} ne 'HTTP/1.0'
             && !Plack::Util::status_with_no_entity_body($res->[0])
             && $env->{'REQUEST_METHOD'} ne 'HEAD'
             && !$h->exists('Transfer-Encoding')
            ) {
                $h->set('Transfer-Encoding' => 'gzip');
                my $encoder = Plack::Middleware::Deflater::Encoder->new('gzip');
                # normal response
                if ($res->[2] && ref $res->[2] && ref $res->[2] eq ref []) {
                    my $buf = '';
                    foreach (@{ $res->[2] }) {
                        $buf .= $encoder->print($_) if defined $_;
                    }
                    $buf .= $encoder->close;
                    $res->[2] = [$buf];
                    return;
                }
                # delayed or stream
                return sub {
                    $encoder->print(shift);
                };
            }
        });
    } else {
        return $res;
    }
}
