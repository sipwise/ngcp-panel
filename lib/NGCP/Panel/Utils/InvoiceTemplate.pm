package NGCP::Panel::Utils::InvoiceTemplate;
#it should be part of real model, or subcontroller

use strict;
use warnings;
#use Moose;
use Sipwise::Base;
use File::Temp qw/tempfile tempdir/;
use File::Path qw/mkpath/;

sub getDefaultInvoiceTemplate{
    my (%in) = @_;
    #in future may be we will store root default in Db too, but now it is convenient to edit template as file
    my $result = $in{c}->view('SVG')->getTemplateContent($in{c}, 'invoice/invoice_template_'.$in{type}.'.tt');
    
    #$in{c}->log->debug("result=$result;");
    
    if( $result && exists $in{result} ){
        ${$in{result}} = $result;
    }
    return \$result;
}
sub convertSvg2Pdf{
    my($c,$svg_ref,$in,$out) = @_;
    my $svg = $$svg_ref;
    my(@pages) = $svg=~/(<svg.*?(?:\/svg>))/sig;
    
    #$c->log->debug($svg);
    my ($tempdirbase,$tempdir );
    #my($fh, $tempfilename) = tempfile();
    $tempdirbase = join('/',File::Spec->tmpdir,@$in{qw/provider_id tt_type tt_sourcestate/}, $out->{tt_id});
    ! -e $tempdirbase and mkpath( $tempdirbase, 0, 0777 );
    $tempdir = tempdir( DIR =>  $tempdirbase , CLEANUP => 0 );
    #print "tempdirbase=$tempdirbase; tempdir=$tempdir;$!;\n\n\n";
    $c and $c->log->debug("tempdirbase=$tempdirbase; tempdir=$tempdir;");
    #try{
    #} catch($e){
    #    NGCP::Panel::Utils::Message->error(
    #        c => $c,
    #        error => "Can't create temporary directory at: $tempdirbase;" ,
    #        desc  => $c->loc("Can't create temporary directory."),
    #    );
    #}
    my $pagenum = 1;
    my @pagefiles;
    foreach my $page (@pages){
        my $fh;
        my $pagefile = "$tempdir/$pagenum.svg";
        push @pagefiles, $pagefile;
        open($fh,">",$pagefile);
        #try{
        #} catch($e){
        #    NGCP::Panel::Utils::Message->error(
        #        c => $c,
        #        error => "Can't create temporary page file at: $tempdirbase/$page.svg;" ,
        #        desc  => $c->loc("Can't create temporary file."),
        #    );
        #}
        print $fh $page;
        close $fh;
        $pagenum++;
    }
    
    my $cmd = "rsvg-convert -f pdf ".join(" ", @pagefiles);
    #print $cmd;
    #die();
    $c and $c->log->debug($cmd);
    #$cmd = "chmod ugo+rwx $filename";
    #binmode(STDIN);
    #$out->{tt_string_pdf} = `$cmd`;
    {
        #$cmd = "fc-list";
        open B, "$cmd |"; 
        binmode B; 
        local $/ = undef; 
        $out->{tt_string_pdf} = <B>;
        $c->log->error("Pipe: close: !=$!; ?=$?;");
        close B or ($? == 0 ) or $c->log->error("Error closing rsvg pipe: close: $!;");
    }
}
sub preprocessInvoiceTemplateSvg{
    my($in,$svg_ref) = @_;
    no warnings 'uninitialized';
    #print "1.\n\n\n\n\nsvg=".$out->{tt_string_prepared}.";";
    $$svg_ref=~s/(?:{\s*)?<!--{|}-->(?:\s*})?//gs;
    $$svg_ref=~s/(<g .*?(id *=["' ]+(?:title|bg|mid)page["' ]+)?.*?)(?:display="none")(?(2)(?:.*?>)($2.*?>))/$1$3/gs;
    if($in->{no_fake_data}){
        $$svg_ref=~s/\[%[^\[\%]+lorem.*?%\]//gs;        
    }
    #print "\n\n2.\n\n\n\nsvg=".$out->{tt_string_prepared}.";";
}

1;