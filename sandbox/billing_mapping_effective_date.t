use strict;
use warnings;

use Test::More;
use DateTime::Format::ISO8601 qw();
use DateTime::TimeZone qw();
use Tie::IxHash;

# try using the db directly ...
my $schema = undef;
eval '
    use lib "/home/rkrenn/sipwise/git/ngcp-schema/lib";
    use lib "/home/rkrenn/sipwise/git/sipwise-base/lib";
    use NGCP::Schema;
';
unless ($@) {
    diag("connecting to ngcp db");
    $schema = NGCP::Schema->connect({
        dsn                 => "DBI:mysql:database=provisioning;host=192.168.0.29;port=3306",
        user                => "root",
        #password            => "hYdpKVwJwKLhrz7THr44",
        mysql_enable_utf8   => "1",
        on_connect_do       => "SET NAMES utf8mb4",
        quote_char          => "`",
    });
}
# ... or a separate csv file otherwise:
my $filename = 'api_balanceintervals_test_reference.csv';

test_contracts(sub {
    my $contract = shift;

    #use Data::Dumper;
    #print Dumper($contract)."\n";

    ### the "scanline":

    # 1. prepare the interval tree and event list:
    my $tree = IntervalTree->new();
    my %mappings = ();
    my $event_list = create_linked_hash();
    foreach my $mapping (@{$contract->{mappings}}) {
        my $id = $mapping->{id};
        $mappings{$id} = $mapping;
        my $s = $mapping->{start_date};
        $s = $contract->{contract_create} unless $s;
        $s = dt_from_string($s)->epoch;
        my $e = $mapping->{end_date};
        if ($e) {
            $e = dt_from_string($e)->epoch;
        } else {
            $e = 2147483647;
        }
        $tree->insert($s,$e,$id);
        $event_list->Push($s => $id);
        $event_list->Push($e => $id);
    }

    # 2. sort events by time ascending:
    $event_list->Reorder( sort { $a <=> $b } $event_list->Keys );

    # 3. generate the "effective start" list by determining the mappings effective at any event time:
    my $effective_start_list = create_linked_hash();
    foreach my $t ($event_list->Keys) {
        my $msec = 0.000;
        foreach my $id (sort { $a <=> $b } @{$tree->find($t)}) { # sort by max(billing_mapping_id)
            if ($effective_start_list->EXISTS($t + $msec)) {
                die("MUST NOT HAPPEN");
            } else {
                $effective_start_list->Push(($t + $msec) => $mappings{$id});
                $msec += 0.001; # to allow unique effective start times per contract, we use microsecond resolution
            }
        }
    }

    # 4. done, save it.

    # 5. test it with actual billing mapping impl:
    my @past_mappings = ();
    foreach my $t ($effective_start_list->Keys) {
        if ($t <= $contract->{now}) {
            push(@past_mappings,$effective_start_list->FETCH($t));
        }
    }
    is(pop(@past_mappings)->{id},$contract->{bm_actual_id},"xxxx");

});

done_testing;

sub create_linked_hash {
    my %hash = ();
    return tie(%hash, 'Tie::IxHash');
}

sub test_contracts {
    my $code = shift;

    if ($schema) {
        my $contract_rs = $schema->resultset("contracts");
        my $page = 1;
        my $now = DateTime->now(
            time_zone => DateTime::TimeZone->new(name => 'local')
        );
        my $dtf = $schema->storage->datetime_parser;
        while (my @page = $contract_rs->search_rs(undef,{
            page => $page,
            rows => 100,
        })->all) {
            foreach my $contract (@page) {
                my $bm_actual_id = $schema->resultset('contracts')->search_rs({
                    id => $contract->id,
                },{
                    bind    => [ ( $dtf->format_datetime($now) ) x 2, ( $contract->id ) x 2 ],
                    'join'  => 'billing_mappings_actual',
                    '+select' => [ 'billing_mappings_actual.actual_bm_id' ],
                    '+as' => [ 'billing_mapping_id' ],
                })->first->get_column("billing_mapping_id");

                &$code({
                    now => $now->epoch,
                    contract_id => $contract->id,
                    contract_create => dt_to_string($contract->create_timestamp // $contract->modify_timestamp),
                    bm_actual_id => $bm_actual_id,
                    mappings => [ map {
                        my %mapping = $_->get_inflated_columns;
                        $mapping{profile_id} = delete $mapping{billing_profile_id};
                        $mapping{start_date} = dt_to_string($mapping{start_date});
                        $mapping{end_date} = dt_to_string($mapping{end_date});
                        $mapping{network_name} = $_->billing_profile->name;
                        $mapping{network_id} //= '';
                        $mapping{network_name} = ($_->network ? $_->network->name : '');
                        $mapping{product_class} = $_->product->class;
                        \%mapping;
                    } $contract->billing_mappings->all ],
                });
            }
            $page++;
        }
    } else {
        #select
        #  now(),
        #  c.id,
        #  if(c.create_timestamp = "0000-00-00 00:00:00",c.modify_timestamp,c.create_timestamp),
        #  bm_actual.id,
        #  bm.id,
        #  bm.start_date,
        #  bm.end_date,
        #  p.id,
        #  p.name,
        #  n.id,
        #  n.name,
        #  product.id,
        #  product.class
        #from
        #          billing.contracts c
        #join      billing.billing_mappings bm on c.id = bm.contract_id
        #join      billing.billing_profiles p on p.id = bm.billing_profile_id
        #left join billing.billing_networks n on n.id = bm.network_id
        #join      billing.products product on product.id = bm.product_id
        #join      (
        #          select
        #            bm1.contract_id,
        #            max(bm1.id) as id
        #          from
        #            billing.billing_mappings bm1
        #          join (
        #               select
        #                 bm2.contract_id,
        #                 max(bm2.start_date) as start_date
        #               from
        #                 billing.billing_mappings bm2
        #               where (
        #                 bm2.end_date >= now() or bm2.end_date is null)
        #                 and (bm2.start_date <= now() or bm2.start_date is null
        #               ) group by bm2.contract_id
        #          ) as mx on bm1.contract_id = mx.contract_id and bm1.start_date <=> mx.start_date
        #          group by bm1.contract_id
        #          ) as bm_actual on bm_actual.contract_id = c.id
        ##where
        ##bm.contract_id in ( 60725,60722,60718,60685,60697,60734,60728,60716,60698,60705,60701,60717,60707,60712,60709,60733,60715,60721,60695,60692,60674,60680,60699,60730,60689,60682,60687,60691,60706,60702,60703,60676,60708,60675,60711,60683,60681,60700,60732,60678,60688,60684,60710,60720,60714,60686,60731,60726,60677,60713,60719,60723,60693,60694,60727,60704,60724,60690,60729,60696,60673,60679 )
        ##limit 10;
        #order by c.id
        #into outfile 'api_balanceintervals_test_reference.csv' fields terminated by ',' lines terminated by '\n';
        open(my $fh, '<:encoding(UTF-8)', $filename) or die "Could not open file '$filename' $!";
        my $old_contract_id = undef;
        my $contract = undef;
        while (my $row = <$fh>) {
            my @cleaned = map { $_ =~ s/\\N//g; $_ =~ s/[\r\n]//gi; $_; } split(/,/,$row);
            my ($now,$contract_id,$contract_create,$bm_actual_id,$id,$start_date,$end_date,
                $profile_id,$profile_name,$network_id,$network_name,$product_id,$product_class) = @cleaned;
            #print join("\t",@cleaned) . "\n";
            my $mappings;
            if (not defined $old_contract_id or $contract_id != $old_contract_id) {
                &$code($contract) if $contract;
                $contract->{now} = dt_from_string($now)->epoch;
                $contract->{contract_id} = $contract_id;
                $contract->{contract_create} = dt_from_string($contract_create);
                $contract->{bm_actual_id} = $bm_actual_id;
                $mappings = [];
                $contract->{mappings} = $mappings;
            } else {
                $mappings = $contract->{mappings};
            }
            push(@$mappings,{
                id => $id,
                contract_id => $contract_id,
                start_date => dt_from_string($start_date),
                end_date => dt_from_string($end_date),
                profile_id => $profile_id,
                profile_name => $profile_name,
                network_id => $network_id,
                network_name => $network_name,
                product_id => $product_id,
                product_class => $product_class,
            });
        }
        &$code($contract) if $contract;
        close $fh;
    }

}

sub dt_to_string {
    my ($dt) = @_;
    return '' unless defined ($dt);
    my $s = $dt->ymd('-') . ' ' . $dt->hms(':');
    $s .= '.'.$dt->millisecond if $dt->millisecond > 0.0;
    return $s;
}

sub dt_from_string {
    my $s = shift;

    # if date is passed like xxxx-xx (as from monthpicker field), add a day
    $s = $s . "-01" if($s =~ /^\d{4}\-\d{2}$/);
    $s = $s . "T00:00:00" if($s =~ /^\d{4}\-\d{2}-\d{2}$/);

    # just for convenience, if date is passed like xxxx-xx-xx xx:xx:xx,
    # convert it to xxxx-xx-xxTxx:xx:xx
    $s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
    my $ts = DateTime::Format::ISO8601->parse_datetime($s);
    $ts->set_time_zone( DateTime::TimeZone->new(name => 'local') );
    return $ts;
}

{

    package IntervalTree;

    #use 5.006;
    #use POSIX qw(ceil);
    #use List::Util qw(max min);
    use strict;
    use warnings;
    #no warnings 'once';

    #use NGCP::Panel::Utils::IntervalTree::Node;

    #our $VERSION = '0.05';

    sub new {
        my ($class) = @_;
        my $self = {};
        $self->{root} = undef;
        return bless $self, $class;
    }

    sub insert {
        my ($self, $start, $end, $value) = @_;
        if (!defined $self->{root}) {
            $self->{root} = IntervalTree::Node->new($start, $end, $value);
        } else {
            $self->{root} = $self->{root}->insert($start, $end, $value);
        }
    }

    sub intersect {
        my ( $self, $start, $end ) = @_;
        if (!defined $self->{root}) {
            return [];
        }
        return $self->{root}->intersect($start, $end);
    }

    sub find {
        my ( $self, $t ) = @_;
        if (!defined $self->{root}) {
            return [];
        }
        return $self->{root}->find($t);
    }

    1;

}

{

    package IntervalTree::Node;

    use strict;
    use warnings;

    use POSIX ();
    use List::Util qw(min max);

    my $EMPTY_NODE;

    sub _nlog {
        return -1.0 / log(0.5);
    }

    sub EMPTY_NODE {
        unless ($EMPTY_NODE) {
            $EMPTY_NODE = IntervalTree::Node->new(0, 0, undef,1);
        }
        return $EMPTY_NODE;
    }

    sub left_node {
        my ($self) = @_;
        return $self->{cleft} != IntervalTree::Node::EMPTY_NODE ? $self->{cleft} : undef;
    }

    sub right_node {
        my ($self) = @_;
        return $self->{cright} != IntervalTree::Node::EMPTY_NODE ? $self->{cright}  : undef;
    }

    sub root_node {
        my ($self) = @_;
        return $self->{croot} != IntervalTree::Node::EMPTY_NODE ? $self->{croot} : undef;
    }

    sub new {
        my ($class, $start, $end, $interval, $emptynode) = @_;
        # Perl lacks the binomial distribution, so we convert a
        # uniform into a binomial because it naturally scales with
        # tree size.  Also, perl's uniform is perfect since the
        # upper limit is not inclusive, which gives us undefined here.
        my $self = {};
        $self->{priority} = POSIX::ceil(_nlog() * log(-1.0/(1.0 * rand() - 1)));
        $self->{start}    = $start;
        $self->{end}      = $end;
        $self->{interval} = $interval;
        $self->{maxend}   = $end;
        $self->{minstart} = $start;
        $self->{minend}   = $end;
        $self->{cleft}    = ($emptynode ? undef : IntervalTree::Node::EMPTY_NODE);
        $self->{cright}   = ($emptynode ? undef : IntervalTree::Node::EMPTY_NODE);
        $self->{croot}    = ($emptynode ? undef : IntervalTree::Node::EMPTY_NODE);
        return bless $self, $class;
    }

    sub insert {
        my ($self, $start, $end, $interval) = @_;
        my $croot = $self;
        # If starts are the same, decide which to add interval to based on
        # end, thus maintaining sortedness relative to start/end
        my $decision_endpoint = $start;
        if ($start == $self->{start}) {
            $decision_endpoint = $end;
        }

        if ($decision_endpoint > $self->{start}) {
            # insert to cright tree
            if ($self->{cright} != IntervalTree::Node::EMPTY_NODE) {
                $self->{cright} = $self->{cright}->insert( $start, $end, $interval );
            } else {
                $self->{cright} = IntervalTree::Node->new( $start, $end, $interval );
            }
            # rebalance tree
            if ($self->{priority} < $self->{cright}{priority}) {
                $croot = $self->rotate_left();
            }
        } else {
            # insert to cleft tree
            if ($self->{cleft} != IntervalTree::Node::EMPTY_NODE) {
                $self->{cleft} = $self->{cleft}->insert( $start, $end, $interval);
            } else {
                $self->{cleft} = IntervalTree::Node->new( $start, $end, $interval);
            }
            # rebalance tree
            if ($self->{priority} < $self->{cleft}{priority}) {
                $croot = $self->rotate_right();
            }
        }

        $croot->set_ends();
        $self->{cleft}{croot}  = $croot;
        $self->{cright}{croot} = $croot;
        return $croot;
    }

    sub rotate_right {
        my ($self) = @_;
        my $croot = $self->{cleft};
        $self->{cleft}  = $self->{cleft}{cright};
        $croot->{cright} = $self;
        $self->set_ends();
        return $croot;
    }

    sub rotate_left {
        my ($self) = @_;
        my $croot = $self->{cright};
        $self->{cright} = $self->{cright}{cleft};
        $croot->{cleft}  = $self;
        $self->set_ends();
        return $croot;
    }

    sub set_ends {
        my ($self) = @_;
        if ($self->{cright} != IntervalTree::Node::EMPTY_NODE && $self->{cleft} != IntervalTree::Node::EMPTY_NODE) {
            $self->{maxend} = max($self->{end}, $self->{cright}{maxend}, $self->{cleft}{maxend});
            $self->{minend} = min($self->{end}, $self->{cright}{minend}, $self->{cleft}{minend});
            $self->{minstart} = min($self->{start}, $self->{cright}{minstart}, $self->{cleft}{minstart});
        } elsif ( $self->{cright} != IntervalTree::Node::EMPTY_NODE) {
            $self->{maxend} = max($self->{end}, $self->{cright}{maxend});
            $self->{minend} = min($self->{end}, $self->{cright}{minend});
            $self->{minstart} = min($self->{start}, $self->{cright}{minstart});
        } elsif ( $self->{cleft} != IntervalTree::Node::EMPTY_NODE) {
            $self->{maxend} = max($self->{end}, $self->{cleft}{maxend});
            $self->{minend} = min($self->{end}, $self->{cleft}{minend});
            $self->{minstart} = min($self->{start}, $self->{cleft}{minstart});
        }
    }

    sub intersect {
        my ( $self, $start, $end, $sort ) = @_;
        $sort = 1 if !defined $sort;
        my $results = [];
        $self->_intersect( $start, $end, $results );
        return $results;
    }

    sub _intersect {
        my ( $self, $start, $end, $results) = @_;
        # Left subtree
        if ($self->{cleft} != IntervalTree::Node::EMPTY_NODE && $self->{cleft}{maxend} > $start) {
            $self->{cleft}->_intersect( $start, $end, $results );
        }
        # This interval
        if (( $self->{end} > $start ) && ( $self->{start} < $end )) {
            push @$results, $self->{interval};
        }
        # Right subtree
        if ($self->{cright} != IntervalTree::Node::EMPTY_NODE && $self->{start} < $end) {
            $self->{cright}->_intersect( $start, $end, $results );
        }
    }

    sub find {
        my ( $self, $t, $sort ) = @_;
        $sort = 1 if !defined $sort;
        my $results = [];
        $self->_find( $t, $results );
        return $results;
    }

    sub _find {
        my ( $self, $t, $results) = @_;
        # Left subtree
        if ($self->{cleft} != IntervalTree::Node::EMPTY_NODE && $self->{cleft}{maxend} >= $t) {
            $self->{cleft}->_find( $t, $results );
        }
        # This interval
        if (( $self->{end} >= $t ) && ( $self->{start} <= $t )) {
            push @$results, $self->{interval};
        }
        # Right subtree
        if ($self->{cright} != IntervalTree::Node::EMPTY_NODE && $self->{start} <= $t) {
            $self->{cright}->_find( $t, $results );
        }
    }

    1;

}
