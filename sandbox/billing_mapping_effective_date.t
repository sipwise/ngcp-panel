use strict;
use warnings;

use Test::More;
use DateTime::Format::ISO8601 qw();
use DateTime::TimeZone qw();
use Time::HiRes qw(time);
use Tie::IxHash;

# try using the db directly ...
my $schema = undef;

eval 'use lib "/home/rkrenn/sipwise/git/ngcp-schema/lib";';
eval 'use lib "/home/rkrenn/sipwise/git/sipwise-base/lib";';
eval 'use NGCP::Schema;';

print $@;
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

my @perl_records = ();
my @sql_records = ();

#goto SKIP;
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
        if ($s) {
            $s = dt_from_string($s)->epoch;
        } else {
            $s = 0;
        }
        #$s = $contract->{contract_create} unless $s;
        #$s = dt_from_string($s)->epoch;
        my $e = $mapping->{end_date};
        my $e_tree;
        if ($e) {
            $e = dt_from_string($e)->epoch;
            $e_tree = $e;
        } else {
            $e_tree = 2147483647.0;
            $e = $e_tree - 0.001;
        }
        $tree->insert($s,$e_tree,$id);
        $mapping->{"s"} = $s;
        $mapping->{"e"} = $e;
        $event_list->Push($s."-0" => $id);
        $event_list->Push($e."-1" => $id);
    }

    #if ($contract->{contract_id} == 89) {
    #    print "blah";
    #}

    # 2. sort events by time ascending:
    $event_list->Reorder( sort { my ($t_a,$is_end_a) = split(/-/,$a); my ($t_b,$is_end_b) = split(/-/,$b); $t_a <=> $t_b || $is_end_a <=> $is_end_b; } $event_list->Keys );

    # 3. generate the "effective start" list by determining the mappings effective at any event time:
    my @effective_start_list = ();
    my $old_bm_ids = '';
    foreach my $se ($event_list->Keys) {
        my ($t,$is_end) = split(/-/,$se);
        my @group = ();
        my $max_bm_id;
        my $bm_ids = "";
        my $max_s;
        foreach my $id (sort { $mappings{$b}->{"s"} <=> $mappings{$a}->{"s"} || $mappings{$a}->{id} <=> $mappings{$b}->{id}; } @{$tree->find($t)}) { # sort by max(billing_mapping_id)
            my $mapping = $mappings{$id};
            if ($is_end) {
                next if $mapping->{"e"} == $t;
            }
            $max_s = $mapping->{"s"} unless defined $max_s;
            last unless $max_s == $mapping->{"s"};
            my $row = {
                contract_id => $contract->{contract_id},
                billing_mapping_id => $id,
                "last" => 0,
                start_date => ($mapping->{start_date} ? $mapping->{start_date} : undef),
                end_date => ($mapping->{end_date} ? $mapping->{end_date} : undef),
                effective_start_date => sprintf("%.3f",($is_end ? $t + 0.001 : $t)),
                profile_id => $mapping->{profile_id},
                network_id => ($mapping->{network_id} ? $mapping->{network_id} : undef),
            };
            push(@group,$row);
            $max_bm_id = $id;
            $bm_ids .= '-' . $id;
        }
        foreach my $row (@group) {
            $row->{"last"} = ($max_bm_id == $row->{billing_mapping_id} ? 1 : 0);
        }
        if ($old_bm_ids ne $bm_ids) {
            push(@effective_start_list,@group);
        }
        $old_bm_ids = $bm_ids;
    }

    # 4. done (dump the list to db).

    # 5. test it with actual billing mapping impl:
    test_events("perl impl - ",$contract,sub {
        my $now = shift;
        my $bm_actual_id;
        foreach my $row (@effective_start_list) {
            next unless $row->{"last"};
            last if $row->{effective_start_date} > $now;
            $bm_actual_id = $row->{billing_mapping_id};
        }
        return $bm_actual_id;
    },\@effective_start_list);
    push(@perl_records,@effective_start_list);

});

SKIP:
if ($schema) {
    $schema->storage->dbh_do(sub {
        my ($storage, $dbh, @args) = @_;
        $dbh->do('use billing');
        $dbh->do(<<EOS1
create temporary table tmp_transformed (
  contract_id int(11) unsigned,
  billing_mapping_id int(11) unsigned,
  last tinyint(3),
  start_date datetime,
  end_date datetime,
  effective_start_date decimal(13,3),
  profile_id int(11) unsigned,
  network_id int(11) unsigned,
  key tmp_cid_esd_last_idx (contract_id,effective_start_date,last)
);
EOS1
        );
        $dbh->do('drop procedure if exists transform_billing_mappings');
        #$dbh->do('delimiter ;;');
        $dbh->do(<<EOS2
create procedure transform_billing_mappings() begin

  declare _contracts_done, _events_done, _mappings_done, _is_end boolean default false;
  declare _contract_id, _bm_id, _default_bm_id, _profile_id, _network_id int(11) unsigned;
  declare _t, _start_date, _end_date datetime;
  declare _effective_start_time decimal(13,3);
  declare _bm_ids, _old_bm_ids varchar(65535);

  declare contracts_cur cursor for select contract_id
    from billing_mappings bm group by contract_id;
  declare continue handler for not found set _contracts_done = true;

  set _old_bm_ids = "";

  open contracts_cur;
  contracts_loop: loop
    fetch contracts_cur into _contract_id;
    if _contracts_done then
      leave contracts_loop;
    end if;
    nested1: begin

      declare events_cur cursor for select t,is_end from (
#        (select coalesce(bm.start_date,if(c.create_timestamp = "0000-00-00 00:00:00",c.modify_timestamp,c.create_timestamp)) as t, 0 as is_end
        (select coalesce(bm.start_date,from_unixtime(0)) as t, 0 as is_end
          from billing_mappings bm join contracts c on bm.contract_id = c.id where contract_id = _contract_id)
        union all
        (select coalesce(end_date,from_unixtime(2147483647) - 0.001) as t, 1 as is_end from billing_mappings where contract_id = _contract_id)
      ) as events group by t, is_end order by t, is_end;
      declare continue handler for not found set _events_done = true;

      set _events_done = false;
      open events_cur;
      events_loop: loop
        fetch events_cur into _t, _is_end;
        if _events_done then
          leave events_loop;
        end if;

        nested2: begin

          declare mappings_cur cursor for select bm1.id, bm1.start_date, bm1.end_date, bm1.billing_profile_id, bm1.network_id from
              billing_mappings bm1 where bm1.contract_id = _contract_id and bm1.start_date <=> (select bm2.start_date
              from billing_mappings bm2 where
              bm2.contract_id = _contract_id
              and (bm2.start_date <= _t or bm2.start_date is null)
              and (if(_is_end,bm2.end_date > _t,bm2.end_date >= _t) or bm2.end_date is null)
              order by bm2.start_date desc limit 1) order by bm1.id asc;
          declare continue handler for not found set _mappings_done = true;

          set _effective_start_time = (select unix_timestamp(if(_is_end,_t + 0.001,_t)));
          set _bm_ids = "";
          set _mappings_done = false;
          open mappings_cur;
          mappings_loop1: loop
            fetch mappings_cur into _bm_id, _start_date, _end_date, _profile_id, _network_id;
            if _mappings_done then
              leave mappings_loop1;
            end if;
            set _bm_ids = (select concat(_bm_ids,"-",_bm_id));
            set _default_bm_id = _bm_id;
          end loop mappings_loop1;
          close mappings_cur;

          if _old_bm_ids != _bm_ids then
            set _mappings_done = false;
            open mappings_cur;
            mappings_loop2: loop
              fetch mappings_cur into _bm_id, _start_date, _end_date, _profile_id, _network_id;
              if _mappings_done then
                leave mappings_loop2;
              end if;

              #INSERT......
              #select _contract_id,_effective_start_time,_profile_id, _network_id;
              insert into tmp_transformed values(_contract_id,_bm_id,if(_bm_id = _default_bm_id,1,0),_start_date,_end_date,_effective_start_time,_profile_id,_network_id);

              #set _effective_start_time = _effective_start_time + 0.001;
            end loop mappings_loop2;
            close mappings_cur;
          end if;
          set _old_bm_ids = _bm_ids;
        end nested2;
      end loop events_loop;
      close events_cur;
    end nested1;
  end loop contracts_loop;
  close contracts_cur;
end;;
EOS2
        );
        #$dbh->do('delimiter ;');
        my $t1 = time();
        $dbh->do('call transform_billing_mappings()');
        diag("time to transform all billing_mappings: ".sprintf("%.3f secs",time()-$t1));
        $dbh->do('drop procedure transform_billing_mappings');

    },);

    goto SKIP1;
    test_contracts(sub {
        my $contract = shift;
        $schema->storage->dbh_do(sub {
            my ($storage, $dbh, @args) = @_;
            #my $sth = $dbh->prepare("select from_unixtime(tr.effective_start_date) as effective_start_date_epoch,tr.* from tmp_transformed tr where tr.contract_id = ? order by tr.effective_start_date asc");
            my $sth = $dbh->prepare("select * from tmp_transformed tr where tr.contract_id = ? order by tr.effective_start_date asc");
            $sth->execute($contract->{contract_id});
            my $mappings = $sth->fetchall_arrayref({});
            $sth->finish();

            test_events("sql impl - ",$contract,sub {
                my $now = shift;

                my $sth = $dbh->prepare("select max(effective_start_date) from tmp_transformed where contract_id = ? and effective_start_date <= ? and last = 1");
                $sth->execute($contract->{contract_id},$now);
                my ($effective_start_date) = $sth->fetchrow_array();
                $sth = $dbh->prepare("select billing_mapping_id from tmp_transformed where contract_id = ? and effective_start_date = ? and last = 1");
                $sth->execute($contract->{contract_id},$effective_start_date);
                my ($bm_actual_id) = $sth->fetchrow_array();
                $sth->finish();

                unless (defined $bm_actual_id) {
                    $sth = $dbh->prepare("select min(billing_mapping_id) from tmp_transformed where contract_id = ? and last = 1");
                    $sth->execute($contract->{contract_id});
                    ($bm_actual_id) = $sth->fetchrow_array();
                    $sth->finish();
                }
                return $bm_actual_id;
            },$mappings);
            push(@sql_records,@$mappings);

        },);

    });

    {
        is_deeply(\@perl_records,\@sql_records,"compare generated perl and sql effective start date records deeply");
    }

SKIP1:
    {
        my $now = DateTime->now(
            time_zone => DateTime::TimeZone->new(name => 'local')
        );
        my $t1;
        my $billing_mappings_actual_new;
        $schema->storage->dbh_do(sub {
            my ($storage, $dbh, @args) = @_;
            $dbh->do("create temporary table tmp_transformed_copy like tmp_transformed");
            $dbh->do("insert into tmp_transformed_copy select * from tmp_transformed");
            my $sth = $dbh->prepare(<<EOS3
select t2.contract_id,t2.billing_mapping_id from
(select
contract_id,
max(effective_start_date) as effective_start_date
from tmp_transformed
where effective_start_date <= ?
and last = 1
group by contract_id) as t1
join tmp_transformed_copy t2 on t2.contract_id = t1.contract_id and t2.effective_start_date = t1.effective_start_date and t2.last = 1
EOS3
            );
            $t1 = time();
            $sth->execute($now->epoch); #,$contract->{contract_id});
            #my $t2 = Time::Hires::time();
            $billing_mappings_actual_new = $sth->fetchall_arrayref();
            $sth->finish();
            diag("new query (".(scalar @$billing_mappings_actual_new)." mappings): ".sprintf("%.3f secs",time()-$t1));
        });

        my $dtf = $schema->storage->datetime_parser;
        $t1 = time();
        my @billing_mappings_actual_old = map { my %res = $_->get_inflated_columns; [ @res{qw(contract_id actual_bm_id)} ]; } $schema->resultset('billing_mappings_actual')->search_rs(undef,{
            bind    => [ ( $dtf->format_datetime($now) ) x 2, ( undef ) x 2 ],
        })->all;
        diag("old query (".(scalar @$billing_mappings_actual_new)." mappings): ".sprintf("%.3f secs",time()-$t1));
        is_deeply($billing_mappings_actual_new,\@billing_mappings_actual_old,"compare actual_billing_mapping table deeply");

    }
}

done_testing;

sub create_linked_hash {
    my %hash = ();
    return tie(%hash, 'Tie::IxHash');
}

sub test_events {
    my ($label,$contract,$get_actual_billing_mapping,$mappings) = @_;
    my $event_list = create_linked_hash();
    foreach my $mapping (@{$contract->{mappings}}) {
        my $id = $mapping->{id};
        my $s = $mapping->{start_date};
        $s = $contract->{contract_create} unless $s;
        my $e = $mapping->{end_date};
        $e = dt_to_string(DateTime->from_epoch(epoch => 2147483647)) unless $e;
        $event_list->Push($s => $id);
        $event_list->Push($e => $id);
    }

    foreach ($event_list->Keys) {
        my $dt = dt_from_string($_);
        my $i = -1;
        foreach my $dt (dt_from_string($_)->subtract(seconds => 1),dt_from_string($_),dt_from_string($_)->add(seconds => 1)) {
            unless (is(&$get_actual_billing_mapping($dt->epoch),get_actual_billing_mapping($schema,$contract->{contract_id},$dt),
            $label."contract $contract->{contract_id} billing mapping id at t".($i<0?$i:"+$i")." = $dt")) {
                foreach my $row (@$mappings) {
                    print join("\t",(map { "$_=".((not defined $row->{$_}) ? "\t" : $row->{$_}); } sort keys %$row)) . "\n";
                       #print $mapping[0]."\t".$mapping[1]."\t".$mapping[2]."\t".$mapping->{end_date}."\t".$mapping->{profile_id}."\t".$mapping->{network_id}."\n";
                }
            }
            $i++;
        }
    }
}

sub test_contracts {
    my $code = shift;

    if ($schema) {
        my $contract_rs = $schema->resultset("contracts");
        my $page = 1;
        my $now = DateTime->now(
            time_zone => DateTime::TimeZone->new(name => 'local')
        );
        #my $dtf = $schema->storage->datetime_parser;
        while (my @page = $contract_rs->search_rs(undef,{
            page => $page,
            rows => 100,
        })->all) {
            foreach my $contract (@page) {
                my $bm_actual_id = get_actual_billing_mapping($schema,$contract->id,$now);

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
            my @cleaned = map { s/\\N//gr =~ s/[\r\n]//gir; } split(/,/,$row);
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

sub get_actual_billing_mapping {
    my ($schema, $contract_id, $now) = @_;
    my $dtf = $schema->storage->datetime_parser;
    return $schema->resultset('contracts')->search_rs({
                    id => $contract_id,
                },{
                    bind    => [ ( $dtf->format_datetime($now) ) x 2, ( $contract_id ) x 2 ],
                    'join'  => 'billing_mappings_actual',
                    '+select' => [ 'billing_mappings_actual.actual_bm_id' ],
                    '+as' => [ 'billing_mapping_id' ],
                })->first->get_column("billing_mapping_id");

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
        my ( $self, $start, $end ) = @_;
        #$sort = 1 if !defined $sort;
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
        my ( $self, $t ) = @_;
        #$sort = 1 if !defined $sort;
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
