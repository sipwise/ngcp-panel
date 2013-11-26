package NGCP::Panel::Controller::Calls;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Utils::Navigation;
use Number::Phone;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub index :Chained('/') :PathPart('calls') :Args(0) {
    my ( $self, $c ) = @_;

    $c->stash(template => 'calls/chord.tt');
}

sub calls_matrix_ajax :Chained('/') :PathPart('calls/ajax') :Args(0) {
     my ( $self, $c ) = @_;

     my $matrix = [];
     my $countries = [];

     my $rs = $c->model('DB')->resultset('cdr')->search({}, {
        select => [qw/source_cli destination_user_in/],
     });

     my $n = $rs->count;

     my $id_counter = 0;
     my $id_table = {};

     while(my $ref = $rs->next) {
        next unless($ref->source_cli && $ref->source_cli =~ /^\d{5,}$/ && 
            $ref->destination_user_in && $ref->destination_user_in =~ /^\d{5,}$/);
        my $s = Number::Phone->new($ref->source_cli);
        my $d = Number::Phone->new($ref->destination_user_in);
        next unless($s && $d);

        # register new ids for those country codes
        unless(exists $id_table->{$s->country_code}) {
            $id_table->{$s->country_code} = $id_counter;
            $countries->[$id_counter] = $s->country;
            ++$id_counter;
        }
        unless(exists $id_table->{$d->country_code}) {
            $id_table->{$d->country_code} = $id_counter;
            $countries->[$id_counter] = $d->country;
            ++$id_counter;
        }

        my $sid = $id_table->{$s->country_code};
        my $did = $id_table->{$d->country_code};

        unless(defined $matrix->[$sid]) {
            $matrix->[$sid] = [];
        }
        unless(defined $matrix->[$sid]->[$did]) {
            $matrix->[$sid]->[$did] = 1;
        } else {
            $matrix->[$sid]->[$did]++;
        }
     }

     my $count = @{ $countries };
     for(my $i = 0; $i < $count; ++$i) {
        unless(defined $matrix->[$i]) {
            $matrix->[$i] = [];
            $matrix->[$i]->[$count-1] = undef;
        } elsif(@{ $matrix->[$i] } != $count) {
            $matrix->[$i]->[$count-1] = undef;
        }
     }

    my $data = {
        countries => $countries,
        calls => $matrix,
    };
    my $json = JSON->new->allow_nonref;
    $c->res->body($json->encode($data));
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
