#!/usr/bin/perl -w
use strict;

use DBI;
use Data::Dumper;
my $debug = 1;

sub handle_pref;

my ($dbuser, $dbpass);
my $mfile = '/etc/mysql/sipwise.cnf';

if(-f $mfile) {
	open my $fh, "<", $mfile
		or die "failed to open '$mfile': $!\n";
	$_ = <$fh>; chomp;
	s/^SIPWISE_DB_PASSWORD='(.+)'$/$1/;
	$dbuser = 'sipwise'; $dbpass = $_;
} else {
	$dbuser = 'root';
	$dbpass = '';
}
print "using user '$dbuser' with pass '$dbpass'\n"
	if($debug);

my $dbh = DBI->connect('dbi:mysql:provisioning;host=localhost', $dbuser, $dbpass)
	or die "failed to connect to billing DB\n";

my $sub_sth = $dbh->prepare("select ps.uuid as uuid, ps.id as s_id, bs.external_id as s_external_id, ct.external_id as c_external_id from provisioning.voip_subscribers ps left join billing.voip_subscribers bs on ps.uuid = bs.uuid left join billing.contracts ct on bs.contract_id = ct.id order by ps.id asc");
my $prefget_sth = $dbh->prepare("select vup.value from provisioning.voip_usr_preferences vup left join voip_preferences vp on vup.attribute_id = vp.id where vp.attribute = ? and vup.subscriber_id = ?");
my $prefdel_sth = $dbh->prepare("delete vup from provisioning.voip_usr_preferences vup left join voip_preferences vp on vup.attribute_id = vp.id where vp.attribute = ? and vup.subscriber_id = ?");
my $prefup_sth = $dbh->prepare("update provisioning.voip_usr_preferences vup left join voip_preferences vp on vup.attribute_id = vp.id set value = ? where vp.attribute = ? and vup.subscriber_id = ?");
my $prefin_sth = $dbh->prepare("insert into provisioning.voip_usr_preferences values(NULL, ?, (select id from provisioning.voip_preferences where attribute = ?), ?, now())");
my $subup_sth = $dbh->prepare("update billing.voip_subscribers set external_id = null where external_id = ''");
my $conup_sth = $dbh->prepare("update billing.contracts set external_id = null where external_id = ''");

$subup_sth->execute or die "failed to clear empty subscriber external_id\n";
$conup_sth->execute or die "failed to clear empty contract external_id\n";
$sub_sth->execute or die "failed to execute subscriber query\n";

while(my $row = $sub_sth->fetchrow_hashref) {
	
	print Dumper $row if $debug;

	handle_pref($row, 'ext_subscriber_id', 's_external_id');
	handle_pref($row, 'ext_contract_id', 'c_external_id');
}

$sub_sth->finish;
$dbh->disconnect;

sub handle_pref {
	my($row, $p, $name) = @_;

	$prefget_sth->execute($p, $row->{s_id})
		or die "failed to execute $p fetch query\n";
	print "$p has ".$prefget_sth->rows." pref rows\n" if $debug;

	unless($row->{$name}) {
		if($prefget_sth->rows) {
			print "delete $p from prefs as undef in sub\n" if $debug;
			$prefdel_sth->execute($p, $row->{s_id});
		} else {
			print "$p pref not set and not defined in sub, ok\n" if $debug;
		}
	} else {
		if($prefget_sth->rows) {
			print "update $p in prefs\n" if $debug;
			$prefup_sth->execute($row->{$name}, $p, $row->{s_id});
		} else {
			print "insert $p in prefs\n" if $debug;
			$prefin_sth->execute($row->{s_id}, $p, $row->{$name});
		}
	}
	$prefget_sth->finish;
	$prefdel_sth->finish;
	$prefup_sth->finish;
	$prefin_sth->finish;
}
