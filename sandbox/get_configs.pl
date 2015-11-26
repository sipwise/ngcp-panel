#!/usr/bin/perl
use strict;
use File::Slurp qw/read_file write_file/;
use Data::Dumper;
use DBI;

my $dbcfg = {
    dbdb => 'provisioning',
    dbhost => 'localhost',
    dbuser => 'root',
    dbpass => '',
};

my $dbh = DBI->connect('dbi:mysql:'.$dbcfg->{dbdb}.';host='.$dbcfg->{dbhost}, $dbcfg->{dbuser}, $dbcfg->{dbpass}, {mysql_enable_utf8 => 1})
    or die "failed to connect to billing DB\n";

foreach my $cfg_row( @{$dbh->selectall_arrayref('select c.device_id,d.reseller_id, d.model,d.vendor, c.data from autoprov_devices d inner join autoprov_configs c on d.id=c.device_id where d.vendor="Yealink"',  { Slice => {} } ) } ){
    my $config_type='';
    $cfg_row->{model} =~s/^ +//g;
    $cfg_row->{model} =~s/[ \+]+/_/g;
    if($cfg_row->{vendor} =~/Yealink/i){
        if($cfg_row->{model} =~/T19/i || $cfg_row->{model}=~/T4/i){
            $config_type = "t19_t4x";
        }elsif($cfg_row->{model}=~/T19/i){
            $config_type = "w52";
        }else{
            $config_type = "txx";
        }
        $config_type .= "_";
    }
    print "model=$cfg_row->{model},vendor=$cfg_row->{vendor},device_id=$cfg_row->{device_id},config_type=$config_type;\n";
    write_file("/tmp/$cfg_row->{vendor}_${config_type}$cfg_row->{model}_$cfg_row->{reseller_id}_$cfg_row->{device_id}.txt",\$cfg_row->{data});
}
1;