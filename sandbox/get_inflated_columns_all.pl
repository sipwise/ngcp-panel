#!/usr/bin/perl

use strict;

use Data::Dumper;
use NGCP::Schema;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);
use Safe::Isa qw($_isa);

my $logger = Log::Log4perl->get_logger('NGCP::Panel');
my $schema = NGCP::Schema->connect();
my $dbh = $schema->storage->dbh;
use Test::MockObject;
my $c_mock = Test::MockObject->new();
my $user_mock = Test::MockObject->new();
$user_mock->set_always( 'roles' => 'reseller' );
$c_mock->set_always( 'log' => $logger )->set_always( 'model' => $schema )->set_always( 'user' => $user_mock );



my $cnt = 1000;
my $devmod_id = 1;


my $time = time;
for(my $i=0; $i<$cnt; $i++){
    my $dev_pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
        c => $c_mock,
        type => 'dev',
        id =>  $devmod_id,
    );
    my $pref_values = get_inflated_columns_all($dev_pref_rs,'hash' => 'attribute', 'column' => 'value', 'force_array' => 1);
}
print "pure.time=".(time-$time).";\n";

my $time = time;
for(my $i=0; $i<$cnt; $i++){
    my $devprof_pref_rs = $c_mock->model('DB')
        ->resultset('voip_preferences')
        ->search({
            'profile.id' => $devmod_id,
        },{
            prefetch => {'voip_devprof_preferences' => 'profile'},
    });
    my %pref_values;
    foreach my $value($devprof_pref_rs->all) {
        $pref_values{$value->attribute} =
            [ map {$_->value} $value->voip_devprof_preferences->all ];
    }
}
print "DBIx.time=".(time-$time).";\n";

#pure.time=5;
#DBIx.time=14;
r
1;