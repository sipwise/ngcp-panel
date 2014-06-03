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
    my($svg_ref) = @_;
    
    my $xp = XML::XPath->new($$svg_ref);
    
    my $g = $xp->find('//g[@id[contains(.,"page")]]');
    foreach my $node($g->get_nodelist) {
        if($node->getAttribute('display')) {
            $node->removeAttribute('display');
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
        },
        customer => {
            id => rand(10000)+10000,
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
        },
        calls => [
            map {{ 
                start_time => time,
                source_customer_cost => rand(1000),
                duration => rand(7200) + 10,
                destination_user_in => "1".$_."1234567890",
                call_type => (qw/cfu cfb cft cfna/)[rand 4],
                zone => "Zone $_",
                zone_detail => "Detail $_",
            }}(1 .. 100)
        ],
        zones => [
            map {{ 
                number => rand(200),
                cost => rand(10000),
                duration => rand(10000),
                free_time => 0,
                zone => "Zone $_",
                zone_detail => "Detail $_",
            }}(1 .. 15)
        ],
    };
}

1;
# vim: set tabstop=4 expandtab:
