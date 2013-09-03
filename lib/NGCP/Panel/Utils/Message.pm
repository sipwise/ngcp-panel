package NGCP::Panel::Utils::Message;

use Catalyst;
use Sipwise::Base;

method error ($self: Catalyst :$c, Str :$desc, Str :$log?, :$error?) {
# we explicitly declare the invocant to skip the validation for Object
# because we want a class method instead of an object method
    if (defined $log) {
        $c->log->error($log);
        $c->flash(messages => [{type => 'error', text => $desc}]);
        return;
    }

    unless (defined $error) {
        $c->log->error("$desc (no detailed information available)");
        $c->flash(messages => [{type => 'error', text => "$desc"}]);
        return;
    }
    
    if (my ($host) = $error =~ /problem connecting to (\S+, port [0-9]+)/ ) {
        $c->log->error("$desc ($error)");
        $c->flash(messages => [{type => 'error', text => "$desc (A service could not be reached, $host)"}]);
        return;
    }

    unless ( $error->isa('DBIx::Class::Exception') ) {
        $c->log->error("$desc ($error)");
        $c->flash(messages => [{type => 'error', text => $desc}]);
        return;
    }

    if ( my ($dup) = $error =~ /(Duplicate entry \S*)/ ) {
        $c->log->error("$desc ($error)");
        $c->flash(messages => [{type => 'error', text => "$desc ($dup)"}]);
        return;
    }

    if ( my ($excerpt) = $error =~ /(Column \S+ cannot be null)/ ) {
        $c->log->error("$desc ($error)");
        $c->flash(messages => [{type => 'error', text => "$desc ($excerpt)"}]);
        return;
    }

    $c->log->error("$desc ($error)");
    $c->flash(messages => [{type => 'error', text => $desc}]);
    return;
}

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Utils::Message

=head1 DESCRIPTION

Parse messages for log and Web display.

=head1 INTERFACE

=head2 Functions

=head3 C<error>

Params: c (required), desc (required), error, log

Parse Exceptions (mainly DBIx::Class::Exceptions) and show the relevant
bits on the panel. Also log everything to the logger.

=head1 AUTHOR

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.
