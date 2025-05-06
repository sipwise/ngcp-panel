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
        #password            => "...",
        mysql_enable_utf8   => "1",
        on_connect_do       => "SET NAMES utf8mb4",
        quote_char          => "`",
    });
    ok($schema->source("contracts")->add_relationship(
        "billing_mappings_actual_old",
        "NGCP::Schema::Result::billing_mappings_actual",
        { "foreign.contract_id" => "self.id" },
        { cascade_copy => 0, cascade_delete => 0 },
        "multi",
    ),"legacy billing_mappings_actual relationship registered");
    #ok($schema->source("contracts")->add_relationship(
    #    "billing_mappings_old",
    #    "NGCP::Schema::Result::billing_mappings",
    #    { "foreign.contract_id" => "self.id" },
    #    { cascade_copy => 0, cascade_delete => 0 },
    #    "multi",
    #),"legacy billing_mappings relationship registered");
}
# ... or a separate csv file otherwise:
my $filename = 'api_balanceintervals_test_reference.csv';

my @perl_records = ();
my @sql_records = ();

#goto SKIP;
test_contracts(sub {
    my $contract = shift;

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
        my $bm_actual;
        foreach my $row (@effective_start_list) {
            next unless $row->{"last"};
            last if $row->{effective_start_date} > $now;
            $bm_actual = { %$row };
            delete $bm_actual->{last};
            delete $bm_actual->{billing_mapping_id};
            delete $bm_actual->{effective_start_date};
            $bm_actual->{billing_profile_id} = delete $bm_actual->{profile_id};
        }
        return $bm_actual;
    },\@effective_start_list);
    push(@perl_records,[ map { delete $_->{billing_mapping_id}; $_; }
            sort { ($a->{effective_start_date} <=> $b->{effective_start_date}) || ($a->{billing_mapping_id} <=> $b->{billing_mapping_id}) } @effective_start_list ]);

});

#SKIP:
if ($schema) {
    $schema->storage->dbh_do(sub {
        my ($storage, $dbh, @args) = @_;
        $dbh->do('use billing');
        $dbh->do(<<EOS1
create temporary table tmp_contracts_billing_profile_network (
  id int(11) unsigned not null auto_increment,
  contract_id int(11) unsigned not null,
  billing_profile_id int(11) unsigned not null,
  billing_network_id int(11) unsigned default null,
  start_date datetime,
  end_date datetime,
  base tinyint(3) not null default 0,
  primary key (id),
  unique key cbpn_natural_idx (contract_id, billing_profile_id, billing_network_id, start_date, end_date, base)
) engine=InnoDB default charset=utf8;
EOS1
        );
        $dbh->do(<<EOS2
create temporary table tmp_contracts_billing_profile_network_schedule (
  id int(11) unsigned not null auto_increment,
  profile_network_id int(11) unsigned not null,
  effective_start_time decimal(13,3) not null,
  primary key (id),
  key cbpns_pnid_est_idx (profile_network_id,effective_start_time)
) engine=InnoDB default charset=utf8;
EOS2
        );
        $dbh->do(<<EOS3
create or replace procedure tmp_insert_billing_profile_network_schedule(
  _contract_id int(11) unsigned,
  _last tinyint(3),
  _start_date datetime,
  _end_date datetime,
  _effective_start_date decimal(13,3),
  _profile_id int(11) unsigned,
  _network_id int(11) unsigned
) begin

  declare _profile_network_id int(11) unsigned;

  set _profile_network_id = (select id from tmp_contracts_billing_profile_network where contract_id = _contract_id and billing_profile_id = _profile_id and billing_network_id <=> _network_id and start_date <=> _start_date and end_date <=> _end_date and base = _last);

  if _profile_network_id is null then
    insert into tmp_contracts_billing_profile_network values(null,_contract_id,_profile_id,_network_id,_start_date,_end_date,_last);
    set _profile_network_id = last_insert_id();
  end if;
  insert into tmp_contracts_billing_profile_network_schedule values(null,_profile_network_id,_effective_start_date);

end;;
EOS3
        );
        $dbh->do(<<EOS4
create or replace procedure tmp_transform_billing_mappings() begin

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

              call tmp_insert_billing_profile_network_schedule(_contract_id,if(_bm_id = _default_bm_id,1,0),_start_date,_end_date,_effective_start_time,_profile_id,_network_id);

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
EOS4
        );
        my $t1 = time();
        $dbh->do('call tmp_transform_billing_mappings()');
        diag("time to transform all billing_mappings: ".sprintf("%.3f secs",time()-$t1));
        $dbh->do('drop procedure tmp_transform_billing_mappings');
        $dbh->do(<<EOS5
create or replace function tmp_get_profile_network(
  _contract_id int(11),
  _epoch decimal(13,3)
) returns int(11)
reads sql data
begin

  declare _effective_start_date decimal(13,3);
  declare _cbpn_id int(11);

  if _contract_id is null or _epoch is null then
    return null;
  end if;

  set _effective_start_date = (select max(cbpns.effective_start_time) from tmp_contracts_billing_profile_network_schedule cbpns join
    tmp_contracts_billing_profile_network cbpn on cbpn.id = cbpns.profile_network_id
    where cbpn.contract_id = _contract_id and cbpns.effective_start_time <= _epoch and cbpn.base = 1);

  if _effective_start_date is null then
    set _cbpn_id = (select min(id) from tmp_contracts_billing_profile_network cbpn
      where cbpn.contract_id = _contract_id and cbpn.base = 1);
  else
    set _cbpn_id = (select cbpn.id from tmp_contracts_billing_profile_network_schedule cbpns join
      tmp_contracts_billing_profile_network cbpn on cbpn.id = cbpns.profile_network_id
      where cbpn.contract_id = _contract_id and cbpns.effective_start_time = _effective_start_date and cbpn.base = 1);
  end if;

  return _cbpn_id;

end;;
EOS5
        );
    },);

    #goto SKIP1;
    test_contracts(sub {
        my $contract = shift;
        $schema->storage->dbh_do(sub {
            my ($storage, $dbh, @args) = @_;
            my $sth = $dbh->prepare(<<EOS5
select
  tcbpn.id as cbpn_id,
  tcbpn.contract_id as contract_id,
  tcbpn.base as last,
  tcbpn.start_date as start_date,
  tcbpn.end_date as end_date,
  tcbpns.effective_start_time as effective_start_date,
  tcbpn.billing_profile_id as billing_profile_id,
  tcbpn.billing_network_id as network_id
from
     tmp_contracts_billing_profile_network_schedule tcbpns
join tmp_contracts_billing_profile_network tcbpn on tcbpns.profile_network_id = tcbpn.id
where
  tcbpn.contract_id = ?
EOS5
            );
            $sth->execute($contract->{contract_id});
            my $mappings = $sth->fetchall_hashref("cbpn_id");
            $sth->execute($contract->{contract_id});
            my $all_mappings = $sth->fetchall_arrayref({});
            $sth->finish();

            test_events("sql impl - ",$contract,sub {
                my ($now,$mappings) = @_;


                my $sth = $dbh->prepare("select tmp_get_profile_network(?,?)");
                $sth->execute($contract->{contract_id},$now);
                my ($cbpn_id) = $sth->fetchrow_array();
                $sth->finish();

                my %got = %{$mappings->{$cbpn_id}};
                delete $got{cbpn_id};
                delete $got{effective_start_date};
                delete $got{last};

                return \%got;
            },$mappings);
            push(@sql_records,[ map { delete $_->{cbpn_id}; $_->{profile_id} = delete $_->{billing_profile_id}; $_; }
                sort { ($a->{effective_start_date} <=> $b->{effective_start_date}) ||
                    ($a->{cbpn_id} <=> $b->{cbpn_id}) } @$all_mappings ]);

            $sth = $dbh->prepare(<<EOS6
select
  contract_id,
  start_date,
  end_date,
  billing_profile_id as billing_profile_id,
  billing_network_id as network_id
from
     tmp_contracts_billing_profile_network tcbpn
join tmp_contracts_billing_profile_network_schedule tcbpns on tcbpns.profile_network_id = tcbpn.id
where
  tcbpn.contract_id = ?
and floor(tcbpns.effective_start_time) = tcbpns.effective_start_time
order by tcbpns.effective_start_time asc, tcbpns.profile_network_id asc

EOS6
            );
            $sth->execute($contract->{contract_id});
            my $got_bm = $sth->fetchall_arrayref({});
            $sth->finish();

            $sth = $dbh->prepare("select contract_id,start_date,end_date,billing_profile_id,network_id from billing_mappings where contract_id = ? order by start_date asc, id asc");
            $sth->execute($contract->{contract_id});
            my $expected_bm = $sth->fetchall_arrayref({});
            $sth->finish();

            is_deeply($got_bm,$expected_bm,"fetching all contract id $contract->{contract_id} mappings deeply");

        },);

    });

    {
        is_deeply(\@sql_records,\@perl_records,"compare generated perl and sql effective start date records deeply");
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
            $dbh->do("create temporary table tmp_contracts_billing_profile_network_schedule_copy like tmp_contracts_billing_profile_network_schedule");
            $dbh->do("insert into tmp_contracts_billing_profile_network_schedule_copy select * from tmp_contracts_billing_profile_network_schedule");
            $dbh->do("create temporary table tmp_contracts_billing_profile_network_copy like tmp_contracts_billing_profile_network");
            $dbh->do("insert into tmp_contracts_billing_profile_network_copy select * from tmp_contracts_billing_profile_network");
            my $now_epoch = $now->epoch;
            my $sth = $dbh->prepare(<<EOS7
select
  est.contract_id as contract_id,
  cbpn.start_date,
  cbpn.end_date,
  cbpn.billing_profile_id as billing_profile_id,
  cbpn.billing_network_id as network_id
from
     tmp_contracts_billing_profile_network_schedule cbpns
join tmp_contracts_billing_profile_network cbpn on cbpns.profile_network_id = cbpn.id
join (select
  cbpn.contract_id as contract_id,
  max(cbpns.effective_start_time) as effective_start_time
from tmp_contracts_billing_profile_network_schedule_copy cbpns
join tmp_contracts_billing_profile_network_copy cbpn on cbpns.profile_network_id = cbpn.id
where cbpns.effective_start_time <= $now_epoch and cbpn.base = 1
group by cbpn.contract_id) est on est.contract_id = cbpn.contract_id and cbpns.effective_start_time = est.effective_start_time
where cbpn.base = 1;
EOS7
            );
            $t1 = time();
            $sth->execute();
            $billing_mappings_actual_new = $sth->fetchall_arrayref({});
            $sth->finish();
            diag("new query (".(scalar @$billing_mappings_actual_new)." mappings): ".sprintf("%.3f secs",time()-$t1));
        });

        my $dtf = $schema->storage->datetime_parser;
        $t1 = time();
        my @billing_mappings_actual_old = $schema->resultset('billing_mappings_actual')->search_rs(undef,{
            bind    => [ ( $dtf->format_datetime($now) ) x 2, ( undef ) x 2 ],
        })->all;
        diag("old query (".(scalar @$billing_mappings_actual_new)." mappings): ".sprintf("%.3f secs",time()-$t1));
        @billing_mappings_actual_old = map { my %res = $schema->resultset('billing_mappings')->find($_->actual_bm_id)->get_inflated_columns;
            delete $res{id};
            delete $res{product_id};
            $res{start_date} = dt_to_string($res{start_date}) if $res{start_date};
            $res{end_date} = dt_to_string($res{end_date}) if $res{end_date};
            \%res; } @billing_mappings_actual_old;
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
            my $got = &$get_actual_billing_mapping($dt->epoch,$mappings);
            my $bm_id = get_actual_billing_mapping_old($schema,$contract->{contract_id},$dt);
            my %expected = $schema->resultset('billing_mappings')->find($bm_id)->get_inflated_columns;
            delete $expected{id};
            delete $expected{product_id};
            $expected{start_date} = dt_to_string($expected{start_date}) if $expected{start_date};
            $expected{end_date} = dt_to_string($expected{end_date}) if $expected{end_date};

            is_deeply($got,\%expected,$label."compare contract $contract->{contract_id} billing mapping id at t".($i<0?$i:"+$i")." = $dt");

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
        while (my @page = $contract_rs->search_rs(undef,{
            page => $page,
            rows => 100,
        })->all) {
            foreach my $contract (@page) {
                my $bm_actual_id = get_actual_billing_mapping_old($schema,$contract->id,$now);
                next unless $bm_actual_id;
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
                    } $schema->resultset('billing_mappings')->search_rs({
                        contract_id => $contract->id,
                    })->all ],
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

sub get_actual_billing_mapping_old {
    my ($schema, $contract_id, $now) = @_;
    my $dtf = $schema->storage->datetime_parser;
    my $contract = $schema->resultset('contracts')->search_rs({
                    id => $contract_id,
                },{
                    bind    => [ ( $dtf->format_datetime($now) ) x 2, ( $contract_id ) x 2 ],
                    'join'  => 'billing_mappings_actual_old',
                    '+select' => [ 'billing_mappings_actual_old.actual_bm_id' ],
                    '+as' => [ 'billing_mapping_id' ],
                })->first;
    return $contract->get_column("billing_mapping_id") if $contract;
    return;

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
