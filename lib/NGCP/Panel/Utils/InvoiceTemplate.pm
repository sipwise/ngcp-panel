package NGCP::Panel::Utils::InvoiceTemplate;

use Sipwise::Base;
use File::Temp;
use XML::XPath;
use IPC::System::Simple qw/capturex/;
use Template;

sub svg_pdf {
    my ($c,$svg_ref,$pdf_ref) = @_;
    my $svg = $$svg_ref;

    my $dir = File::Temp->newdir(undef, CLEANUP => 0);
    my $tempdir = $dir->dirname;
    my $pagenum = 1;
    my @pagefiles;

    # file consists of multiple svg tags (invald!), split them up:
    my(@pages) = $svg=~/(<svg.*?(?:\/svg>))/sig;

    foreach my $page(@pages) {
        my $fh;

        my $pagefile = "$tempdir/$pagenum.svg";
        push @pagefiles, $pagefile;


        print ">>>>>>>>>>>>>>>>>> processing $pagefile\n";

        my $xp = XML::XPath->new($page);
        my $g = $xp->find('//g[contains(@class,"firsty-") and contains(@class,"lasty")]');
        foreach my $node($g->get_nodelist) {
            my $class = $node->getAttribute('class');
            print ">>>>>>>>>>>>>>>>>> got class $class\n";
            my $firsty = $class; my $lasty = $class;

            $firsty =~ s/^.+firsty\-(\d+).*$/$1/;
            $lasty =~ s/^.+lasty\-(\d+).*$/$1/;
            if(length($firsty) && length($lasty)) {
                print ">>>>>>>>>>>> we got firsty=$firsty and lasty=$lasty\n";
                process_child_nodes($node, $firsty, $lasty);
            }
        }
        $page = ($xp->findnodes('/'))[0]->toString();


        open($fh, ">", $pagefile);
        binmode($fh, ":utf8");
        print $fh $page;
        close $fh;

        $pagenum++;
    }

    # For whatever reason, the pdf looks ok with zoom of 1.0 when
    # generated via rsvg-convert, but the print result is too big,
    # so we need to scale it down by 0.8 to get a mediabox of 595,842
    # when using 90dpi.
    # (it doesn't happen with inkscape, no idea what rsvg does)
    my @cmd_args = (qw/-a -f pdf -z 0.8/, @pagefiles);
    $$pdf_ref = capturex([0], "/usr/bin/rsvg-convert", @cmd_args);

    return 1;
}

sub preprocess_svg {
    my($svg_ref) = @_;
    
    my $xp = XML::XPath->new($$svg_ref);
    
    my $g = $xp->find('//g[@class="page"]');
    foreach my $node($g->get_nodelist) {
        if($node->getAttribute('display')) {
            $node->removeAttribute('display');
        }
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

sub process_child_nodes {
    my ($node, $firsty, $y) = @_;
    for my $attr (qw/y y1 y2/) {
        my $a = $node->getAttribute($attr);
        if($a) {
            $a =~ s/^(\d+)\w*$/$1/;
            my $delta = $a - $firsty;
            my $newy = $y + $delta;

            print ">>>>>>>>>>>>>> attr=$attr, firsty=$firsty, a=$a, delta=$delta, new=$newy\n";
            $node->removeAttribute($attr);
            $node->appendAttribute(XML::XPath::Node::Attribute->new($attr, $newy."mm"));
        }
    }
    my @children = $node->getChildNodes();
    foreach my $node(@children) {
        process_child_nodes($node, $firsty, $y);
    }
}

sub get_dummy_data {
    return {
        rescontact => {
            gender => 'male',
            firstname => 'Resellerfirst',
            lastname => 'Resellerlast',
            comregnum => 'COMREG1234567890',
            company => 'Resellercompany Inc.',
            street => 'Resellerstreet 12/3',
            postcode => '12345',
            city => 'Resellercity',
            country => 'Resellercountry',
            phonenumber => '+1234567890',
            mobilenumber => '+2234567890',
            faxnumber => '+3234567890',
            iban => 'RESIBAN1234567890',
            bic => 'RESBIC1234567890',
            vatnum => 'RESVAT1234567890',
        },
        customer => {
            id => int(rand(10000))+10000,
            external_id => 'Resext1234567890',
        },
        custcontact => {
            gender => 'male',
            firstname => 'Customerfirst',
            lastname => 'Customerlast',
            comregnum => 'COMREG1234567890',
            company => 'Customercompany Inc.',
            street => 'Customerstreet 12/3',
            postcode => '12345',
            city => 'Customercity',
            country => 'Customercountry',
            phonenumber => '+4234567890',
            mobilenumber => '+5234567890',
            faxnumber => '+6234567890',
            iban => 'CUSTIBAN1234567890',
            bic => 'CUSTBIC1234567890',
            vatnum => 'CUSTVAT1234567890',
        },
        billprof => {
            handle => 'BILPROF12345',
            name => 'Test Billing Profile',
            prepaid => 0,
            interval_charge => 29.90,
            interval_free_time => 2000,
            interval_free_cash => 0,
            interval_unit => 'month',
            interval_count => 1,
            currency => 'EUR',
            vat_rate => 20,
            vat_included => 0,
        },
        invoice => {
            year => '2014',
            month => '01',
            serial => '1234567',
            total_net => 12345,
            vat => 12345*0.2,
            total => 12345+(12345*0.2),
        },
        calls => [
            map {{ 
                start_time => time,
                source_customer_cost => int(rand(100000)),
                duration => int(rand(7200)) + 10,
                destination_user_in => "1".$_."1234567890",
                call_type => (qw/cfu cfb cft cfna/)[int(rand 4)],
                zone => "Zone $_",
                zone_detail => "Detail $_",
            }}(1 .. 50)
        ],
        zones => {
            totalcost => int(rand(10000))+10000,
            data => [
                map {{ 
                    number => int(rand(200)),
                    cost => int(rand(100000)),
                    duration => int(rand(10000)),
                    free_time => 0,
                    zone => "Zone $_",
                    zone_detail => "Detail $_",
                }}(1 .. 5)
            ],
        },
    };

}

1;
# vim: set tabstop=4 expandtab:
