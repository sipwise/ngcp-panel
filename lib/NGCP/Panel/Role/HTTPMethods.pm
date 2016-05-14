package NGCP::Panel::Role::HTTPMethods;

#this is duplicated from Catalyst::ActionRole::HTTPMethods
#which is still present with Catalyst::Controller.
#therefore methods required the 'ngcp_' prefix in order to
#avoid naming conflicts.

use Moose::Role;

requires 'match', 'match_captures', 'list_extra_info';

around ['match','match_captures'] => sub {
  my ($orig, $self, $ctx, @args) = @_;
  #my $expected = $ctx->req->method;
  my $expected = $self->_ngcp_normalize_expected_http_method($ctx->req);
  return $self->_ngcp_has_expected_http_method($expected) ?
    $self->$orig($ctx, @args) :
    0;
};

sub _ngcp_normalize_expected_http_method {
  my ($self, $req) = @_;
  return $req->header('X-HTTP-Method') ||
    $req->header('X-HTTP-Method-Override') ||
    $req->header('X-METHOD-OVERRIDE') ||
    $req->header('x-tunneled-method') ||
    $req->method;
}

sub _ngcp_has_expected_http_method {
  my ($self, $expected) = @_;
  return 1 unless scalar(my @allowed = $self->ngcp_allowed_http_methods);
  return scalar(grep { lc($_) eq lc($expected) } @allowed) ?
    1 : 0;
}

sub ngcp_allowed_http_methods { @{shift->attributes->{Method}||[]} }

around 'list_extra_info' => sub {
  my ($orig, $self, @args) = @_;
  return {
    %{ $self->$orig(@args) },
    HTTP_METHODS => [sort $self->ngcp_allowed_http_methods],
  };
};

1;
