#!/usr/bin/perl
use lib qw(/root/VMHost/ngcp-panel/t/lib);
use strict;
use warnings;

use Test::Collection;
use Data::Dumper;
use URI::Escape;

my $test_collection = Test::Collection->new(
    name => 'pbxdeviceprofiles', 
    DEBUG => 1,
);
$test_collection->DEBUG_ONLY(0);
my $profiles = $test_collection->get_collection_hal('pbxdeviceprofiles','/api/pbxdeviceprofiles/?name='.uri_escape('*two*'));
$test_collection->DEBUG_ONLY(1);
if($profiles && $profiles->{total_count}){
    foreach my $profile(@{$profiles->{collection}}){
        my $name_new = $profile->{content}->{name};
        $name_new =~s/ \+ two / + 2x/i;
        $test_collection->request_patch(
            [ { op => 'replace', path => '/name', value =>  "$name_new"} ],
            $profile->{location} 
        );
    }
}

$test_collection->name('pbxdevicemodels');
$test_collection->DEBUG_ONLY(0);
my $models = $test_collection->get_collection_hal('pbxdevicemodels','/api/pbxdevicemodels/?model='.uri_escape('*two*'));
$test_collection->DEBUG_ONLY(1);
if($models && $models->{total_count}){
    foreach my $model(@{$models->{collection}}){
        my $name_new = $model->{content}->{model};
        $name_new =~s/ \+ two / + 2x/i;
        $test_collection->request_patch(
            [ { op => 'replace', path => '/model', value =>  "$name_new"} ],
            $model->{location} 
        );
    }
}
