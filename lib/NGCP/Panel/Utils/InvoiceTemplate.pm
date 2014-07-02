package NGCP::Panel::Utils::InvoiceTemplate;

use Sipwise::Base;
use File::Temp;
use XML::XPath;
use IPC::System::Simple qw/capturex/;
use Template;

sub svg_pdf {
    my ($c,$svg_ref,$pdf_ref) = @_;
    my $svg = $$svg_ref;

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

        my $xp = XML::XPath->new($page);
        my $g = $xp->find('//g[contains(@class,"firsty-") and contains(@class,"lasty")]');
        foreach my $node($g->get_nodelist) {
            my $class = $node->getAttribute('class');
            my $firsty = $class; my $lasty = $class;

            $firsty =~ s/^.+firsty\-(\d+).*$/$1/;
            $lasty =~ s/^.+lasty\-(\d+).*$/$1/;
            if(length($firsty) && length($lasty)) {
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
    my $cmd = 'rsvg-convert';
    my $cmd_full = $cmd.' '.join(' ', @cmd_args);
    $c and $c->log->debug( $cmd_full );
    print  $cmd_full.";\n";
    $$pdf_ref = capturex([0], $cmd, @cmd_args);

    return 1;
}

sub preprocess_svg {
    my($svg_ref) = @_;

    $$svg_ref=~s/(?:{\s*)?<!--{|}-->(?:\s*})?//gs;
    $$svg_ref = '<root>'.$$svg_ref.'</root>';

    my $xp = XML::XPath->new($$svg_ref);
    
    my $g = $xp->find('//g[@class="page"]');
    foreach my $node($g->get_nodelist) {
        if($node->getAttribute('display')) {
            $node->removeAttribute('display');
        }
    }
    
    $$svg_ref = ($xp->findnodes('/'))[0]->toString();
    $$svg_ref =~s/^<root>|<\/root>$//;
    
    #$$svg_ref=~s/<(g .*?)(?:display\s*=\s*["']*none["'[:blank:]]+)(.*?id *=["' ]+page[^"' ]*["' ]+)([^>]*)>/<$1$2$3>/gs;
    #$$svg_ref=~s/<(g .*?)(id *=["' ]+page[^"' ]*["' ]+.*?)(?:display\s*=\s*["']*none["'[:blank:]]+)([^>]*)>/<$1$2$3>/gs;
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
    #we do here nothing against TemplateToolkit code invasion - is it correct?
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

sub svg_content{
    my ($c, $content) = @_;
    
    if(!$content) {
        #default is the same for all - I would like to move it as something constant to itils
        my $default = 'invoice/default/invoice_template_svg.tt';
        my $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();

        try {
            $content = $t->context->insert($default);
        } catch($e) {
            # TODO: handle error!
            $c and $c->log->error("failed to load default invoice template: $e");
            return;
        }
    }

    # some part of the chain doesn't like content being encoded as utf8 at that poing
    # already; decode here, and umlauts etc will be fine througout the chain.
    # TODO: doesn't work when loaded from db?
    use utf8;
    utf8::decode($content);
    return $content;
}
sub process_child_nodes {
    my ($node, $firsty, $y) = @_;
    for my $attr (qw/y y1 y2/) {
        my $a = $node->getAttribute($attr);
        if($a) {
            $a =~ s/^(\d+)\w*$/$1/;
            my $delta = $a - $firsty;
            my $newy = $y + $delta;

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
            bankname => 'Resellerbank',
            vatnum => 'RESVAT1234567890',
            gpp0 => 'RESGPP0',
            gpp1 => 'RESGPP1',
            gpp2 => 'RESGPP2',
            gpp3 => 'RESGPP3',
            gpp4 => 'RESGPP4',
            gpp5 => 'RESGPP5',
            gpp6 => 'RESGPP6',
            gpp7 => 'RESGPP7',
            gpp8 => 'RESGPP8',
            gpp9 => 'RESGPP9',
        },
        customer => {
            id => int(rand(10000))+10000,
            external_id => 'Resext1234567890',
            vat_rate => 20,
            add_vat => 0,
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
            bankname => 'Customerbank',
            gpp0 => 'CUSTGPP0',
            gpp1 => 'CUSTGPP1',
            gpp2 => 'CUSTGPP2',
            gpp3 => 'CUSTGPP3',
            gpp4 => 'CUSTGPP4',
            gpp5 => 'CUSTGPP5',
            gpp6 => 'CUSTGPP6',
            gpp7 => 'CUSTGPP7',
            gpp8 => 'CUSTGPP8',
            gpp9 => 'CUSTGPP9',
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
        },
        invoice => {
            period_start => NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month'),
            period_end => NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month')->add(months => 1)->subtract(seconds => 1),
            serial => '1234567',
            amount_net => 12345,
            amount_vat => 12345*0.2,
            amount_total => 12345+(12345*0.2),
        },
        calls => [
            map {{ 
                source_user => 'user',
                source_domain => 'example.org',
                source_cli => '1234567890',
                destination_user_in => "1".$_."1234567890",
                start_time => time,
                source_customer_cost => int(rand(100000)),
                duration => int(rand(7200)) + 10,
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
