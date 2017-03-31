package NGCP::Panel::Role::HTTPMethods;

use Moose::Role;

requires 'match', 'match_captures', 'list_extra_info';

my @METHOD_OVERRIDE_HEADER_NAMES = qw(
  X-HTTP-Method
  X-HTTP-Method-Override
  X-METHOD-OVERRIDE
  x-tunneled-method
);

around ['match','match_captures'] => sub {
  my ($orig, $self, $ctx, @args) = @_;
  my $expected = $self->_normalize_expected_http_method($ctx->req);
  return $self->_XXX_has_expected_http_method($expected) ?
    $self->$orig($ctx, @args) : 0;
};

sub _normalize_expected_http_method {
  my ($self, $req) = @_;
  foreach my $header (@METHOD_OVERRIDE_HEADER_NAMES) {
    my $override = $req->header($header);
    if (defined $override and length($override) > 0) {
      return $override;
    }
  }
  return $req->method;
}

sub _XXX_has_expected_http_method { #todo: rename
  my ($self, $expected) = @_;
  return 1 unless scalar(my @allowed = $self->XXX_allowed_http_methods);
  return scalar(grep { lc($_) eq lc($expected) } @allowed) ? 1 : 0;
}

sub XXX_allowed_http_methods { #todo: rename
  my $action = shift;
  return @{ $action->attributes->{Method} // [] };
}

around 'list_extra_info' => sub {
  my ($orig, $self, @args) = @_;
  return {
    %{ $self->$orig(@args) },
    HTTP_METHODS => [ sort $self->XXX_allowed_http_methods ],
  };
};

1;
