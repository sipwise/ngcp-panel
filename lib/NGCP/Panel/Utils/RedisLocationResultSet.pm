package NGCP::Panel::Utils::RedisLocationResultSet;

use Moose;

use TryCatch;
use NGCP::Panel::Utils::RedisLocationResultSource;

use Data::Dumper;

has _c => (
    is => 'ro',
    isa => 'NGCP::Panel',
);

has _redis => (
    is => 'ro',
    isa => 'Redis',
);

has _rows => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]}
);

has _query_done => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has _domain_resellers => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $h = {};
        my $domres_rs = $self->_c->model('DB')->resultset('domain_resellers')->search(undef, {
            join => 'domain'
        });
        while ((my $res = $domres_rs->next)) {
            $h->{$res->domain->domain} = $res->reseller_id;
        }
        return $h;
    },
);

sub count {
    my ($self) = @_;

    my $count = @{ $self->_rows };
    return $count;
}

sub first {
    my ($self) = @_;
    return $self->_rows->[0];
}

sub all {
    my ($self) = @_;
    return @{ $self->_rows };
}

sub find {
    my ($self, $filter) = @_;
    my $id;

    if (ref $filter eq "") {
        $id = $filter;
        $filter = { id => $id };
    } elsif(ref $filter eq "HASH" && exists $filter->{id}) {
        $id = $filter->{id};
    } else {
        $self->_c->log->error("id filter is mandatory for redis find()");
        return;
    }

    my %entry = $self->_redis->hgetall("location:entry::$id");
    $entry{id} = $entry{ruid};
    if (exists $filter->{reseller_id} && $filter->{reseller_id} != $self->_domain_resellers->{$entry{domain}}) {
        return;
    }
    return NGCP::Panel::Utils::RedisLocationResultSource->new(_data => \%entry);
}

sub search {
    my ($self, $filter, $opt) = @_;
    $filter //= {};

    my $new_rs = $self->meta->clone_object($self);
    unless ($new_rs->_query_done) {
        if ($filter->{id}) {
            push @{ $new_rs->_rows }, $new_rs->find($filter);
        } elsif ($filter->{username} && $filter->{domain}) {
            push @{ $new_rs->_rows },
                @{ $new_rs->_rows_from_mapkey("location:usrdom::" .
                    $filter->{username} . ":" . $filter->{domain}, $filter) };
        } else {
            $new_rs->_scan($filter);
        }
        $new_rs->_query_done(1);
    }
    $new_rs->_filter($filter);

    if ($opt->{order_by}->{'-desc'}) {
        my $f = $opt->{order_by}->{'-desc'};
        $f =~ s/^me\.//;
        $new_rs->_rows([sort { $b->$f cmp $a->$f } @{ $new_rs->_rows }]);
    } elsif ($opt->{order_by}->{'-asc'} || ref $opt->{order_by} eq "") {
        my $f = $opt->{order_by}->{'-asc'} // $opt->{order_by};
        $f =~ s/^me\.//;
        $new_rs->_rows([sort { $a->$f cmp $b->$f } @{ $new_rs->_rows }]);
    }

    $opt->{rows} //= -1;
    $opt->{offset} //= 0;
    if (!defined $opt->{page} && $opt->{rows} > -1 || $opt->{offset} > 0) {
        $new_rs->_rows([ splice @{ $new_rs->_rows }, $opt->{offset}, $opt->{rows} ]);   
    }

    if (defined $opt->{page} && $opt->{rows} > 0) {
        $new_rs->_rows([ splice(@{ $new_rs->_rows }, ($opt->{page} - 1 )*$opt->{rows}, $opt->{rows}) ]);
    }
    return $new_rs;
}

sub _rows_from_mapkey {
    my ($self, $mapkey, $filter) = @_;
    my @rows = ();
    my $keys = $self->_redis->smembers($mapkey);
    foreach my $key (@{ $keys }) {
        my %entry = $self->_redis->hgetall($key);
        $entry{id} = $entry{ruid};
        if (exists $filter->{reseller_id} && $filter->{reseller_id} != $self->_domain_resellers->{$entry{domain}}) {
            next;
        }
        my $res = NGCP::Panel::Utils::RedisLocationResultSource->new(_data => \%entry);
        push @rows, $res;
    }
    return \@rows;
}

sub _filter {
    my ($self, $filter) = @_;
    my @newrows = ();
    my $i = 0;
    use irka;
    use Data::Dumper;
    use Carp qw /longmess/;
    irka::loglong(['rows',$self->_rows]);
    irka::loglong(['filter',$filter]);
    foreach my $row (@{ $self->_rows }) {
        my $match = 0;
        my $filter_applied = 0;
        my %attr = map { $_->name => 1 } $row->meta->get_all_attributes;
        foreach my $f (keys %{ $filter }) {
            if ($f eq "-and" && ref $filter->{$f} eq "ARRAY") {
                irka::loglong(['_filter.f',$f]);
                foreach my $andcondition (@{ $filter->{$f} }) {
                    irka::loglong(['_filter.andcondition',$andcondition]);
                    next unless (ref $andcondition eq "ARRAY");
                    irka::loglong(['_filter.andcondition is array']);
                    foreach my $innercol (@{ $andcondition }) {
                        if (ref $innercol eq "HASH") {
                            foreach my $colname (keys %{ $innercol }) {
                                my $searchname = $colname;
                                $colname =~ s/^me\.//;
                                next if ($colname =~ /\./); # we don't support joined table columns
                                $filter_applied = 1;
                                irka::loglong(['_filter.innercol is scalar:', (ref $innercol->{$searchname} eq ""), 'attr exists',(exists $attr{$colname}),'colname',$colname,'$innercol->{$searchname}',$innercol->{$searchname}]);
                                if (ref $innercol->{$searchname} eq "") {
                                    if (!exists $attr{$colname} || lc($row->$colname) ne lc($innercol->{$searchname})) {
                                    } else {
                                    irka::loglong(['_filter.match 1: attr.colname', $attr{$colname}]);
                                        $match = 1;
                                        last;#it means that we will not check other columns from innercols like
                                        #{
                                        #    colname1 => value1,
                                        #    colname2 => value2,
                                        #}
                                        #or logic ?
                                    }
                                } elsif (ref $innercol->{$searchname} eq "HASH" && exists $innercol->{$searchname}->{like}) {
                                    my $fil = $innercol->{$searchname}->{like};
                                    $fil =~ s/^\%//;
                                    $fil =~ s/\%$//;
                                    if (!exists $attr{$colname} || $row->$colname !~ /$fil/i) {
                                    } else {
                                        $match = 1;
                                        last;
                                    }
                                }
                            }#foreach key in hash in '-and' => [[{ here }]]
                            last if ($match);
                        }#if innercol (element of '-and' => [[]] array) is a hash
                    }#foreach element in  '-and' => [[===>HERE<==]]
                }#foreach element in '-and' array ( '-and' => [ here ])
                last if ($match);
            }#key -s '-and' and value is array ref
        }#end of keys of filters, the only possible key is '-and'
        next if ($filter_applied && !$match);
        push @newrows, $row;
    }#end of rows
    irka::loglong(['result',\@newrows]);
    irka::loglong(longmess);
    $self->_rows(\@newrows);
}

sub _scan {
    my ($self, $filter) = @_;
    $filter //= {};
    my $match = ($filter->{username} // "") . ":" . ($filter->{domain} // "");
    if ($match eq ":") {
        $match = "*";
    } elsif ($match =~ /:$/) {
        $match .= '*';
    }

    $self->_rows([]);
    my $cursor = 0;
    do {
        my $res = $self->_redis->scan($cursor, MATCH => "location:usrdom::$match", COUNT => 1000);
        $cursor = shift @{ $res };
        my $mapkeys = shift @{ $res };
        foreach my $mapkey (@{ $mapkeys }) {
            push @{ $self->_rows }, @{ $self->_rows_from_mapkey($mapkey, $filter) };
        }
    } while ($cursor);

    return 1;
}

sub result_class {
    "dummy";
}

sub result_source {
    NGCP::Panel::Utils::RedisLocationResultSource->new;
}

1;
