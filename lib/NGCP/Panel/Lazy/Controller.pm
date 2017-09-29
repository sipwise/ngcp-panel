package NGCP::Panel::Lazy::Controller;
use parent qw/Catalyst::Controller/;

use Class::Load ':all';
use List::Util qw/first/;

# taken from Catalyst::Controller; problem in original code is
# that "$app" has "=HASH..." afterwards, causing the code to
# fail when concatinatig the name with some suffix
sub _expand_role_shortname {
    my ($self, @shortnames) = @_;
    my $app = $self->_application;

    my $prefix = $self->can('_action_role_prefix') ? $self->_action_role_prefix : ['Catalyst::ActionRole::'];
        use Data::Dumper;
        $app->log->error("~~~ in expand role shortname, prefix is " . Dumper $prefix);
        my $appname = "$app"; $appname =~ s/=HASH.+$//;
    my @prefixes = (qq{${appname}::ActionRole::}, @$prefix);
        $app->log->error("~~~ all prefixes are " . (Dumper \@prefixes));

    return String::RewritePrefix->rewrite(
        { ''  => sub {
            my $loaded = load_first_existing_class(
                map { "$_$_[0]" } @prefixes
            );
            return first { $loaded =~ /^$_/ }
              sort { length $b <=> length $a } @prefixes;
          },
          '~' => $prefixes[0],
          '+' => '' },
        @shortnames,
    );
}

1;

