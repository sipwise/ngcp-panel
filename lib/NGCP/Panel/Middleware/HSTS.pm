package NGCP::Panel::Middleware::HSTS;
use Sipwise::Base;
use Plack::Util qw();
extends 'Plack::Middleware';

sub call {
    my ($self, $env) = @_;
    my $res = $self->app->($env);
    $self->response_cb($res, sub {
        my $res = shift;
        my $h = Plack::Util::headers($res->[1]);
        $h->set('Strict-Transport-Security' => 'max-age=86400000');
    });
}
