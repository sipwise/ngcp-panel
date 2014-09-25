#! /usr/bin/perl

use strict;

use Data::Dumper;
use WWW::Mechanize::Firefox;
use DBI;
use DateTime;
use DateTime::Format::ISO8601;

my $datetime = DateTime->from_epoch(
    time_zone => DateTime::TimeZone->new(name => 'local'),
    epoch => time(),
);
my $mech = WWW::Mechanize::Firefox->new();

our $dbh = DBI->connect('dbi:mysql:spider;host=localhost', 'root', '');
our $cfg = {
    url_duplicate_template =>{
        rule => 'deny',
        rule_allow => '',
    }
};

require 'mech_db_create.pm';

our $host = 'https://192.168.56.7:1444';
get_data($mech,$host.'/dashboard');
#while (my $url = $dbh->selectrow_array('select url from url where unix_timestamp(lastvisit) < ? limit 1', undef, $datetime->epoch)){
#    get_data($mech,$url);
#}

sub get_data{
    my ($url_in,$mech,$container_url,$loaded) = {}; 
    ($mech,@{$url_in}{qw/url/},$container_url,$loaded) = @_;
    print "get_data: url=".$url_in->{url}.";\n";
    print "get_data: url=".$url_in->{url}."; container_url=".$container_url->{url}."; loaded=$loaded;\n";

    if(!check_url_toadd($url_in->{url})){
        return;
    }
    my($url) = get_url_db($url_in);
    my($urltemplate) = get_urltemplate_db({
        template => get_urltemplate($url->{url}),
    });

    my $url_toadd = 0;
    if( $url && (!$url->{epoch}) || ( $url->{epoch} < $datetime->epoch) ){
        $url_toadd = 1;
        if($container_url){
            $url_toadd = rule_url_template($container_url,$urltemplate);
        }
    }
    
    if($container_url){#after checking
        register_url_template($container_url,$urltemplate);
    }
    
    if($url_toadd){
        if(!$loaded){
            print "get_data: pre_get_url=".pre_get_url($url->{url}).";\n";
            $mech->get(pre_get_url($url->{url}));
        }else{
            #here add to db urls from clicks, if necessary
        }
        #$mech->eval("alert('QQ');");
        #follow_link starts here. Specially for follow_link we don't need recursion, but for click we do.
        $url->{content} = \$mech->content();
        set_url_visited($url);
        #foreach my $clickable_in ( $mech->clickables()  ) {
        #    my $control = get_control_db({ 
        ##        goto_url_id => $goto_url->{id}, 
        #        label   => process_control_label($clickable_in->{innerHTML}) 
        #    }
        #    );
        #    register_control($url,$control);
        #    #print Dumper $control;
        #    #$mech->click($control);
        #}
        
        
        #my $repl = $mech->repl();
        my $contentDiv;
        eval{
            $contentDiv = $mech->xpath('//div[@id="content"]', single => 1);
        };
        my @links = $mech->find_all_links_dom( $contentDiv ? ( node => $contentDiv )  : () );
        my $link_number = 1;
        foreach my $link ( @links ) {
            print "=============LINKS: $link_number/".($#links + 1)."===============\n";
            print "link href=".$link->{href}.";\n";
            if(!check_url_toadd($link->{href})){
                next;
            }
            my $control_url = { url => process_url($link->{href}) };
            my $goto_url = get_url_db( $control_url );
            if(! ($goto_url)){
                next;
            }
            my $control=get_control_db({ 
                goto_url_id => $goto_url->{id}, 
                label   => process_control_label($link->{innerHTML} || $link->{href}) ,
                #label   => process_control_label($link->text) 
            });
            register_control($url,$control);

            #print Dumper $link;
            #print Dumper { map { $_ => $url->{$_}; } qw/id url urltemplate_id/};
            #print Dumper $control_url;
            #print Dumper $control;
            #print Dumper $link->{tagName};

            if('A' eq $link->{tagName}){#to config
                #get_data($goto_url->{url},$url,1);
                #get_data($goto_url->{url},$url,0);
                #my $mechRecursion = clone($mech);
                $SIG{ALRM} = \&request_timed_out;
                eval {
                    alarm (10);
                    #$mechRecursion->follow_link($link);
                    print "follow_link: \n";
                    print "link href=".$link->{href}."; on the page of url: ".$url->{url}.";\n";
                    $mech->follow_link($link);
                    alarm(0);
                };
                if('link_timed_out' eq $@){
                    print "link hanged\n";
                    print "link href=".$link->{href}."; on the page of url: ".$url->{url}.";\n";
                }else{
                    print "process followed link\n";
                    print "link href=".$link->{href}."; on the page of url: ".$url->{url}.";\n";
                    get_data($mech,$goto_url->{url},$url,1);
                    #get_data($mechRecursion,$goto_url->{url},$url,1);
                    #get_data($mech,$goto_url->{url},$url,0);
                    eval {
                        print "back after link followed\n";
                        print "link href=".$link->{href}."; on the page of url: ".$url->{url}.";\n";
                        alarm (10);
                        $mech->back();
                        alarm(0);
                    };
                }#link pressed successfuly/not successfully
            }#link tag = A, to config later
            $link_number++;
        }#foreach links
    }#container url was to_add successfull
}

sub request_timed_out{
    die("link_timed_out");
}
sub get_url_db{
    my($url) = @_;
    my $url_db;
    if(!($url_db = $dbh->selectrow_hashref('select *,unix_timestamp(lastvisit) as epoch from url where url=?',undef,$url->{url}))){
        $dbh->do('insert into url(url) values(?)',undef,$url->{url});
        $url_db = $url;
        $url_db->{id} = $dbh->last_insert_id(undef,'spider','url','id');
    }
    return $url_db;
}
sub set_url_visited{
    my($url_db) = @_;
    print Dumper [ "update url set lastvisit=from_unixtime(?) where id=?\n", $datetime->epoch, $url_db->{id} ];
    $dbh->do('update url set lastvisit=from_unixtime(?) where id=?',undef,$datetime->epoch,$url_db->{id});
    #die();
    $dbh->do('update url_content set content=? where id=?',undef,${$url_db->{content}},$url_db->{id});
    $dbh->do('delete from url_control where url_id=?',undef,$url_db->{id});
}
sub get_control_db{
    my($control) = @_;
    my $control_db;
    if(!($control_db = $dbh->selectrow_hashref('select * from control where label=? and goto_url_id=?',undef,@$control{qw/label goto_url_id/}))){
        $dbh->do('insert into control(label,goto_url_id) values(?,?)',undef,@$control{qw/label goto_url_id/});
        $control_db = $control;
        $control_db->{id} = $dbh->last_insert_id(undef,'spider','control','id');
        #if(!(my $res=$dbh->selectrow_array('select id from url_variant where url=?'))){
        #    
        #}
    }
    return $control_db;
}
sub register_control{
    my($url,$control) = @_;
    if(!(my $res = $dbh->selectrow_hashref('select * from url_control where url_id=? and control_id=?',undef,$url->{id},$control->{id}))){
        $dbh->do('insert into url_control(url_id,control_id)values(?,?)',undef,$url->{id},$control->{id});
    }
}
sub set_control_db{
    my($control) = @_;
    $dbh->do('update control set label=?,goto_url_id=? where id=?',undef,@$control{qw/label goto_url_id id/});
}
sub get_urltemplate{
    my($url) = @_;
    $url = ~s/\d+/\d+/;
    return $url;
}
sub get_urltemplate_db{
    my($template) = @_;
    my $template_db;
    if(!($template_db = $dbh->selectrow_hashref('select * from urltemplate where template=?',undef,$template->{template}))){
        $dbh->do('insert into urltemplate(template) values(?)',undef,$template->{template});
        $template_db = $template;
        $template_db->{id} = $dbh->last_insert_id(undef,'spider','urltemplate','id');
    }
    return $template_db;
}
sub check_url_toadd{
    my ($url) = @_;
    my $res = 1;
    $url=~s/\s+//g;
    if(!$url){
        $res = 0;
    }
    if($url =~/javascript:;?$/i){
        $res = 0;
    }
    if($url =~/#$/i){
        $res = 0;
    }
    if($url =~/lang=[a-z]{2}/i){
        $res = 0;
    }
    if($url =~/\/back\?/i){
        $res = 0;
    }
    print "check_url_toadd: url=$url; res=$res;\n";
    return $res;
}
sub process_url{
    my ($url) = @_;
    $url=~s/\Q$host\E//;
    $url=~s/[&]?back=[^&]+//;
    $url=~s/\?$//;
    $url=~s/^\/$//;
    return $url;
}
sub pre_get_url{
    my ($url) = @_;
    $url=~s/\Q$host\E//;
    if($url !~/^https?:/){
        $url=$host.'/'.$url;
    }
    $url =~ s!/+!/!g;
    $url =~ s!(https?:(?:\d+)?)/+!$1//!g;
    return $url;
}
sub process_control_label{
    my ($str) = @_;
    $str=~s/^\s*|\s*$//gsm;
    return $str;
}
##--------------------------------------
sub rule_url_template{
    my($container_url,$urltemplate) = @_;
    my $result = 1;
    #here something - if config deny add duplicate template - don't add and parse duplicate url for the same template on the samepage
    #ifconfig specify exceptions for deny - consider it
    #if config specify allow duplicate - add duplicate, and consider defined deny config
    if($cfg->{url_duplicate_template}->{rule} eq 'deny'){
         if(get_registered_url_template($container_url,$urltemplate)){
            $result = 0;
        }
    }
    return $result;
}
sub register_url_template{
    my($container_url,$urltemplate) = @_;
    $dbh->do('insert into url_template(url_id,urltemplate_id)values(?,?)',undef,$container_url->{id},$urltemplate->{id});
}
sub get_registered_url_template{
    my($container_url,$urltemplate) = @_;
    return $dbh->selectrow_array('select urltemplate_id from url_template where url_id=? and urltemplate_id=?',undef,$container_url->{id},$urltemplate->{id});
}
1;

__END__

#use Storable qw/dclone/;
#use Clone 'clone';

# Xvfb :99 &
# DISPLAY=:99 firefox --display=:99 &
## DISPLAY=:99 xdotool search --onlyvisible --title firefox
## DISPLAY=:99 xdotool windowfocus 4194416
# DISPLAY=:99 ~/fillform.pl 

#        $mech->get_local("./test.html");
#        #my $contentDiv = $mech->xpath('//div[@id="content"]', single => 1);
#        my $contentDiv = $mech->xpath('//div[@id="testrow"]', single => 1);
#        #my @links = $mech->find_link_dom( node => $contentDiv, n => 'all' );
#        my @links = $mech->find_all_links_dom( node => $contentDiv );
#        print $#links;
#        die();
