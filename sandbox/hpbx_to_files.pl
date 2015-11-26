#!/usr/bin/perl
use strict;
use File::Slurp qw/read_file write_file/;
use Data::Dumper;


my $str = read_file("device_configs.txt");
my @records = split(/\|\n\|/,$str);
foreach my $record(@records){
    (my($header,$content_2)) = split(/\n/,$record,2);
    my($model,$vendor,$device_id,$content_1) = split(/\s*\|\s*/, $header,4);
    my $content = "$content_1\n$content_2";
    my $config_type='';
    $model=~s/^ +//g;
    $model=~s/[ \+]+/_/g;
    if($vendor =~/Yealink/i){
        if($model=~/T19/i || $model=~/T4/i){
            $config_type = "t19_t4x";
        }elsif($model=~/T19/i){
            $config_type = "w52";
        }else{
            $config_type = "txx";
        }
        $config_type .= "_";
    }
    print "model=$model,vendor=$vendor,device_id=$device_id,config_type=$config_type;\n";
    write_file("./aaa/${vendor}_${config_type}${model}_$device_id.txt",\$content);
}
