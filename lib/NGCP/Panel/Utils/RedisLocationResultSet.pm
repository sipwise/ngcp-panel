package NGCP::Panel::Utils::RedisLocationResultSet;

use Moo;

use TryCatch;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::RedisLocationResultSource;

use Data::Dumper;
use Data::Page;
use Time::HiRes qw(time);
use POSIX qw(strftime);

has usrloc_path => (
    is => 'ro',
    default => '1:location',
);

has _c => (
    is => 'ro',
    isa => sub { die "$_[0] must be NGCP::Panel" unless $_[0] && ref $_[0] eq 'NGCP::Panel' },
);

has _redis => (
    is => 'ro',
    isa => sub { die "$_[0] must be Redis" unless $_[0] && ref $_[0] eq 'Redis' },
);

has _rows => (
    is => 'rw',
    isa => sub { die "$_[0] must be ARRAY" unless $_[0] && ref $_[0] eq 'ARRAY' },
    default => sub {[]}
);

has _query_done => (
    is => 'rw',
    isa => sub { die "$_[0] must be int" unless defined $_[0] && is_int($_[0]) },
    default => 0,
);

has result_source => (
    is => 'ro',
    default => sub { NGCP::Panel::Utils::RedisLocationResultSource->new },
);

has result_class => (
    is => 'ro',
    default => 'dummy',
);

has current_source_alias => (
    is => 'ro',
    default => 'me',
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

    $filter = $self->_unalias($filter);
    if (ref $filter eq "") {
        $id = $filter;
        $filter = { id => $id };
    } elsif(ref $filter eq "HASH" && exists $filter->{id}) {
        $id = $filter->{id};
    } else {
        $self->_c->log->error("id filter is mandatory for redis find()");
        return;
    }

    my %entry = $self->_redis->hgetall($self->usrloc_path.":entry::$id");
    $entry{id} = $entry{ruid};
    return unless $entry{id};
    # deflate expires column
    if ($entry{expires}) {
        $entry{expires} = strftime("%Y-%m-%d %H:%M:%S", localtime($entry{expires}));
    } else {
        $entry{expires} = "1970-01-01 00:00:00";
    }
    my $subscribers_reseller = $self->_c->model('DB')->resultset('provisioning_voip_subscribers')->search(
        {
            '-or' => [
                { 'me.username' => $entry{username} },
                { 'voip_dbaliases.username' => $entry{username}, 'voip_dbaliases.is_devid' => 1 },
            ],
        },
        {
            join => [ { 'contract' => { 'contact' => 'reseller' } }, 'voip_dbaliases' ],
            '+select' => ['reseller.id'],
            '+as' => ['reseller_id']
        }
    )->first;
    return unless $subscribers_reseller;
    if (exists $filter->{reseller_id} && $filter->{reseller_id} != $subscribers_reseller->get_column('reseller_id')) {
        return;
    }
    return NGCP::Panel::Utils::RedisLocationResultSource->new(_data => \%entry);
}

sub search {
    my ($self, $filter, $opt) = @_;
    $filter //= {};

    $filter = $self->_unalias($filter // {});
    my $new_rs = $self->meta->clone_object($self);
    unless ($new_rs->_query_done) {
        if ($filter->{id}) {
            push @{ $new_rs->_rows }, $new_rs->find($filter);
        } elsif ($filter->{username} && ref $filter->{username} eq 'ARRAY') {
            foreach my $username (@{$filter->{username}}) {
                if ($filter->{domain}) {
                    push @{ $new_rs->_rows },
                        @{ $new_rs->_rows_from_mapkey($self->usrloc_path.":usrdom::" .
                            lc($username) . ":" . lc($filter->{domain}), $filter) };
                } else {
                    push @{ $new_rs->_rows },
                        @{ $new_rs->_rows_from_mapkey($self->usrloc_path.":usrdom::" .
                            lc($username), $filter) };
                }
            }
        } elsif ($filter->{username}) {
            if ($filter->{domain}) {
                push @{ $new_rs->_rows },
                    @{ $new_rs->_rows_from_mapkey($self->usrloc_path.":usrdom::" .
                        lc($filter->{username}) . ":" . lc($filter->{domain}), $filter) };
            } else {
                push @{ $new_rs->_rows },
                    @{ $new_rs->_rows_from_mapkey($self->usrloc_path.":usrdom::" .
                        lc($filter->{username}), $filter) };
            }
        } else {
            $new_rs->_scan($filter, $opt);
        }
        $new_rs->_query_done(1);
    }
    #domain and username already handled; if not deleted, would break filtering because of username duality (SCALAR and ARRAY)
    delete $filter->{username};
    delete $filter->{domain};
    $new_rs->_filter($filter);
    if ($opt->{order_by}) {
        my $sort_field;
        my $sort_order = '';
        if (!ref $opt->{order_by}) {
            $sort_field = $opt->{order_by};
        } elsif (ref $opt->{order_by} eq "HASH") {
            if ($opt->{order_by}->{'-desc'}) {
                $sort_field = $opt->{order_by}->{'-desc'};
                $sort_order = 'desc';
            } elsif ($opt->{order_by}->{'-asc'}) {
                $sort_field = $opt->{order_by}->{'-asc'};
            }
        }
        my $source_alias = $self->current_source_alias();
        $sort_field =~ s/^$source_alias\.//;
        if ($sort_order eq 'desc') {
            $new_rs->_rows([sort { $b->$sort_field cmp $a->$sort_field } @{ $new_rs->_rows }]);
        } else {
            $new_rs->_rows([sort { $a->$sort_field cmp $b->$sort_field } @{ $new_rs->_rows }]);
        }
    }

    if ($opt->{page} && $opt->{rows}) {
        my $pager = Data::Page->new();
        $pager->total_entries(scalar @{ $new_rs->_rows });
        $pager->entries_per_page($opt->{rows});
        $pager->current_page($opt->{page});
        $new_rs->_rows([$pager->splice(\@{ $new_rs->_rows })]);
    }

    return $new_rs;
}

sub _rows_from_mapkey {
    my ($self, $mapkey, $filter) = @_;
    my @rows = ();
    my $keys = $self->_redis->smembers($mapkey);
    foreach my $key (@{ $keys }) {
        my $res = $self->_row_from_key($key, $filter);
        push @rows, $res if $res;
    }
    return \@rows;
}

sub _row_from_key {
    my ($self, $key, $filter) = @_;

    my %entry = $self->_redis->hgetall($key);
    $entry{id} = $entry{ruid};
    next unless $entry{id};
    # deflate expires column
    if ($entry{expires}) {
        $entry{expires} = strftime("%Y-%m-%d %H:%M:%S", localtime($entry{expires}));
    } else {
        $entry{expires} = "1970-01-01 00:00:00";
    }
    my $subscribers_reseller = $self->_c->model('DB')->resultset('provisioning_voip_subscribers')->search(
        {
            '-or' => [
                { 'me.username' => $entry{username} },
                { 'voip_dbaliases.username' => $entry{username}, 'voip_dbaliases.is_devid' => 1 },
            ],
        },
        {
            join => [ { 'contract' => { 'contact' => 'reseller' } }, 'voip_dbaliases' ],
            '+select' => ['reseller.id'],
            '+as' => ['reseller_id']
        }
    )->first;
    next unless $subscribers_reseller;
    if (exists $filter->{reseller_id} && $filter->{reseller_id} != $subscribers_reseller->get_column('reseller_id')) {
        return;
    }
    my $res = NGCP::Panel::Utils::RedisLocationResultSource->new(_data => \%entry);
    return $res;
}

sub _filter {
    my ($self, $filter) = @_;
    my @newrows = ();
    my $i = 0;
    foreach my $row (@{ $self->_rows }) {
        my $match = 0;
        my $filter_applied = 0;
        foreach my $colname (keys %{ $filter }) {
            my $condition = $filter->{$colname};
            my $searchname = $colname;
            my $source_alias = $self->current_source_alias();
            $colname =~ s/^$source_alias\.//;
            next if ($colname =~ /\./); # we don't support joined table columns
            $filter_applied = 1;
            if (defined $condition && ref $condition eq "") {
                if ($row->$colname && lc($row->$colname) ne lc($condition)) {
                    $match = 0;
                    last;
                } else {
                    $match = 1;
                }
            } elsif (ref $condition eq "HASH" && exists $condition->{like}) {
                my $fil = $condition->{like};
                $fil =~ s/^\%//;
                $fil =~ s/\%$//;
                if ($row->$colname !~ /$fil/i) {
                    $match = 0;
                    last;
                } else {
                    $match = 1;
                }
            } else { # condition is undef
                if ($row->$colname) {
                    $match = 0;
                    last;
                } else {
                    $match = 1;
                }
            }
        }
        next if ($filter_applied && !$match);
        push @newrows, $row;
    }
    $self->_rows(\@newrows);
}

sub _scan {
    my ($self, $filter, $opt) = @_;
    $filter //= {};
    my $domain = ref $filter->{domain} eq "HASH"
                    ? ''
                    : ($filter->{domain} // "");
    my $match = ($filter->{username} // "") . ":" . ($domain);
    if ($match eq ":") {
        $match = "*";
    } elsif ($match =~ /:$/) {
        if (exists $filter->{domain}) {
            $match = substr($match, 0, -1);
        } else {
            $match .= '*';
        }
    }

    $self->_rows([]);
    if ($match ne '*') {
        my $cursor = 0;
        do {
            my $res = $self->_redis->scan($cursor, MATCH => $self->usrloc_path.":usrdom::$match", COUNT => 1000);
            $cursor = shift @{ $res };
            my $mapkeys = shift @{ $res };
            foreach my $mapkey (@{ $mapkeys }) {
                push @{ $self->_rows }, @{ $self->_rows_from_mapkey($mapkey, $filter) };
            }
        } while ($cursor);
    }
    else {
        my $cursor = -1;
        my $fetched_keys_count = 0;
        my $stored_keys_count = 0;
        my $res;
        my $page = $opt->{page} // 1;
        my $rows = $opt->{rows} // 10;
        while ($cursor) {
            $cursor == -1 and $cursor = 0; # init cursor first iteration
            $res = $self->_redis->scan($cursor, MATCH => $self->usrloc_path.":entry::*", COUNT => 1000);
            $cursor = shift @{ $res };

            last unless $res && ref $res eq 'ARRAY' && $#$res >= 0;

            my $keys = shift @{$res};
            my $keys_count = $#$keys+1;

            my $offset = $fetched_keys_count - ($page-1)*$rows;
            $fetched_keys_count += $keys_count;

            foreach my $key (@{$keys}) {
                if ($offset < 0) {
                    $offset++;
                    next;
                }
                if (my $v = $self->_row_from_key($key)) {
                    push @{$self->_rows}, $v;
                    $stored_keys_count++;
                    last if $stored_keys_count >= $rows;
                }
            }
            last if $stored_keys_count >= $rows;
        }
    }

    return 1;
}

sub _unalias {
    my ($self,$filter) = @_;
    if ('HASH' eq ref $filter) {
        my %unaliased_filter = ();
        my $source_alias = $self->current_source_alias();
        foreach my $key (keys %$filter) {
            my $k = $key;
            $k =~ s/^$source_alias\.//;
            $unaliased_filter{$k} = $filter->{$key};
        }
        $filter = \%unaliased_filter;
    }
    return $filter;
}

1;
