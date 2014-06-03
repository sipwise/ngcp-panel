package NGCP::Panel::Utils::InvoiceTemplate;

use Sipwise::Base;
use File::Temp;
use XML::XPath;
use IPC::System::Simple qw/capturex/;
use Template;

sub svg_pdf {
    my ($c,$svg_ref,$pdf_ref) = @_;
    my $svg = $$svg_ref;

    #my $dir = File::Temp->newdir(); # cleans up automatically leaving scope
    my $dir = File::Temp->newdir(undef, CLEANUP => 1);
    my $tempdir = $dir->dirname;
    my $pagenum = 1;
    my @pagefiles;

    # file consists of multiple svg tags (invald!), split them up:
    my(@pages) = $svg=~/(<svg.*?(?:\/svg>))/sig;

    foreach my $page(@pages) {
        my $fh;

        my $pagefile = "$tempdir/$pagenum.svg";
        push @pagefiles, $pagefile;

        open($fh, ">", $pagefile);
        binmode($fh, ":utf8");
        print $fh $page;
        close $fh;

        $pagenum++;
    }

    my @cmd_args = (qw/-h 849 -w 600 -a -f pdf/, @pagefiles);
    $$pdf_ref = capturex([0], "/usr/bin/rsvg-convert", @cmd_args);

    return 1;
}

sub preprocess_svg {
    my($no_fake_data, $svg_ref) = @_;
    
    my $xp = XML::XPath->new($$svg_ref);
    
    my $g = $xp->find('//g[@id[contains(.,"page")]]');
    foreach my $node($g->get_nodelist) {
        if($node->getAttribute('display')) {
            $node->removeAttribute('display');
        }
    }
    
    if($no_fake_data) {
        my $comment = $xp->find('/comment()[contains(.,"invoice_template_lorem.tt")]');
        foreach my $node($comment->get_nodelist) {
            $node->getParentNode->removeChild($node);
        }
    }
    
    my $comment = $xp->find('//comment()[normalize-space(.) = "{}" or normalize-space(.) = "{ }"]');
    foreach my $node($comment->get_nodelist) {
        $node->getParentNode->removeChild($node);
    }
    
    $$svg_ref = ($xp->findnodes('/'))[0]->toString();
    
    $$svg_ref=~s/(?:{\s*)?<!--{|}-->(?:\s*})?//gs;
    $$svg_ref=~s/<(g .*?)(?:display\s*=\s*["']*none["'[:blank:]]+)(.*?id *=["' ]+page["' ]+)([^>]*)>/<$1$2$3>/gs;
    $$svg_ref=~s/<(g .*?)(id *=["' ]+page["' ]+.*?)(?:display\s*=\s*["']*none["'[:blank:]]+)([^>]*)>/<$1$2$3>/gs;
}

sub sanitize_svg {
    my ($svg_ref) = @_;

    my $xp = XML::XPath->new($$svg_ref);
    
    my $s = $xp->find('//script');
    foreach my $node($s->get_nodelist) {
        if($node->getAttribute('display')) {
            $node->getParentNode->removeChild($node);
        }
    }
    
    $$svg_ref = ($xp->findnodes('/'))[0]->toString();
    return 1;
}

sub get_tt {
    my $tt = Template->new({
        ENCODING => 'UTF-8',
        RELATIVE => 1,
        INCLUDE_PATH => './share/templates:/usr/share/ngcp-panel/templates',
    });
    $tt->context->define_vmethod(
        hash => get_column => sub {
            my($item,$col) = @_;
            if('HASH' eq ref $item){
                return $item->{$col};
            }
        }
    );
    return $tt;
}

1;
# vim: set tabstop=4 expandtab:
