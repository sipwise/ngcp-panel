package NGCP::Panel::Utils::Callflow;
use strict;
use warnings;

use GD::Simple;

sub generate_pcap {
    my $packets = shift;

    my $pcap = pack("LSSlLLL",
        0xa1b2c3d4,     # magic number
        2, 4,           # major/minor version number
        0, 0,           # gmt offset and timestamp accuracy
        0xffff,         # snap length
        1,		# data link type (http://www.tcpdump.org/linktypes.html)
        );

    foreach my $pkg(@{$packets}) {
        my($ts_sec, $ts_usec) = $pkg->timestamp =~ /^(\d+)\.(\d+)$/;
        my $len = length($pkg->header) + length($pkg->payload) + length($pkg->trailer);

        $pcap .= pack("LLLLa*a*a*",
                $ts_sec, $ts_usec,      # timestamp
                $len, $len,             # bytes on-wire/off-wire
                $pkg->header,
                $pkg->payload,
                $pkg->trailer,
                );
    }
    return $pcap;
}

sub draw_line {
  my ($c, $from_x, $from_y, $to_x, $to_y, $width, $color) = @_;
  $c->fgcolor($color);
  $c->moveTo($from_x, $from_y);
  $c->penSize($width, $width);
  $c->lineTo($to_x, $to_y);
}

sub draw_arrow {
  my ($c, $from_x, $from_y, $to_x, $to_y, $width, $color) = @_;
  $c->fgcolor($color);
  $c->moveTo($from_x, $from_y);
  $c->penSize($width, $width);
  $c->lineTo($to_x, $to_y);
  my $poly = new GD::Polygon;
  $poly->addPt($to_x, $to_y);
  my $dir = ($to_x > $from_x) ? -1 : 1;
  $poly->addPt($to_x + 4*$width*$dir, $to_y - 2*$width-(($width%2)?0:1));
  $poly->addPt($to_x + 4*$width*$dir, $to_y + 2*$width);
  my $oldbgcolor = $c->bgcolor();
  $c->bgcolor($color);
  $c->penSize(1,1);
  $c->polygon($poly);
  $c->bgcolor($oldbgcolor);
}

sub draw_text {
  my ($c, $x, $y, $ftype, $fsize, $fcolor, $txt) = @_;
  $c->font($ftype);
  $c->fontsize($fsize);
  $c->fgcolor($fcolor);
  $c->moveTo($x, $y);
  $c->string($txt);
  my @b = $c->stringBounds($txt);
  my %bounds = ('x', $x, 'y', $y, 'dx', $b[0], 'dy', $b[1]);
  return %bounds;
}

sub process_callmap {
    my $c = shift;
    my $packets = shift;
    my $r_png = shift;
    my $r_info = shift;
    my $i = 0;

    my %int_uas = (
      $c->config->{callflow}->{lb_int}, 'lb',
      $c->config->{callflow}->{lb_ext}, 'lb',
      $c->config->{callflow}->{proxy},  'proxy',
      $c->config->{callflow}->{sbc},    'sbc',
      $c->config->{callflow}->{app},    'app',
    );

    my $canvas_margin = 100; # enough free space around diagram for text etc
    my $canvas_elem_distance = 220; # horizontal distance between element lines
    my $canvas_pkg_distance = 30; # vertical distance between packet arrows

    my $canvas_elem_line_width = 2;
    my $canvas_elem_line_color = 'darkgray';
    my $canvas_elem_font = 'Courier:bold';
    my $canvas_elem_font_size = 8;
    my $canvas_elem_font_color = 'darkgray';

    my $canvas_pkg_line_width = 2;
    my $canvas_pkg_line_color = 'green';
    my %canvas_pkg_line_colors = (TCP => 'blue');
    my $canvas_pkg_font = 'Courier:bold';
    my $canvas_pkg_font_size = 8;
    my $canvas_pkg_font_color = 'dimgray';

    my $html_padding = 5;

    my %ext_uas = ();
    my @uas = ();

    ### gather all involved elements
    foreach my $packet(@{$packets}) {
      if(exists($int_uas{$packet->src_ip.':'.$packet->src_port})) {
        #print "skipping internal elem ".$packet->src_ip.':'.$packet->src_port." (".$int_uas{$packet->src_ip.':'.$packet->src_port}.")\n";
        my $ua = $int_uas{$packet->src_ip.':'.$packet->src_port};
        push (@uas, $ua) unless grep {$_ eq $ua} @uas;
      }
      elsif(exists($ext_uas{$packet->src_ip.':'.$packet->src_port})) {
        #print "skipping known external elem ".$packet->src_ip.':'.$packet->src_port."\n";
      }
      else {
        #print "adding new src elem ".$packet->src_ip.':'.$packet->src_port."\n";
        $ext_uas{$packet->src_ip.':'.$packet->src_port} = 1;
        # TODO: prefix "proto:" as well
        push @uas, $packet->src_ip.':'.$packet->src_port;
      }

      if(exists($int_uas{$packet->dst_ip.':'.$packet->dst_port})) {
        #print "skipping internal elem ".$packet->dst_ip.':'.$packet->dst_port." (".$int_uas{$packet->dst_ip.':'.$packet->dst_port}.")\n";
        my $ua = $int_uas{$packet->dst_ip.':'.$packet->dst_port};
        push (@uas, $ua) unless grep {$_ eq $ua} @uas;
      }
      elsif(exists($ext_uas{$packet->dst_ip.':'.$packet->dst_port})) {
        #print "skipping known external elem ".$packet->dst_ip.':'.$packet->dst_port."\n";
      }
      else {
        #print "adding new dst elem ".$packet->dst_ip.':'.$packet->dst_port."\n";
        $ext_uas{$packet->dst_ip.':'.$packet->dst_port} = 1;
        # TODO: prefix "proto:" as well
        push @uas, $packet->dst_ip.':'.$packet->dst_port;
      }
    }

    ### calculate x position of all uas
    my %uas_pos_x = ();
    $i = 0;
    foreach my $ua(@uas) {
      my $name = $ua;
      foreach my $k(keys %int_uas) {
        if($ua eq $int_uas{$k}) {
          $uas_pos_x{$k} = $canvas_margin + $canvas_elem_distance*$i;
        }
      }
      $uas_pos_x{$ua} = $canvas_margin + $canvas_elem_distance*$i;
      ++$i;
    }

    ### calculate canvas size
    # TODO: take into account length of "proto:[ipv6]:port"
    my $canvas_width = 2*$canvas_margin + $canvas_elem_distance*(@uas - 1);
    my $canvas_height = 2*$canvas_margin + $canvas_pkg_distance*(@{$packets} + 1); # leave one pkg_distance free at begin and end
    my $canvas = GD::Simple->new($canvas_width, $canvas_height);
    $canvas->bgcolor('white');

    ### prepare html
    $r_info->{width} = $canvas_width;
    $r_info->{height} = $canvas_height;
    $r_info->{areas} = ();

    ### draw vertical lines
    my $offset = $canvas_margin;
    foreach my $ua(@uas) {
      draw_line($canvas, $offset, $canvas_margin, $offset, $canvas_height-$canvas_margin, $canvas_elem_line_width, $canvas_elem_line_color);
      my @bounds = $canvas->stringBounds($ua); # get bounds for text centering
      draw_text($canvas, $offset-int(abs($bounds[0])/2), $canvas_margin-abs($bounds[1]), $canvas_elem_font, $canvas_elem_font_size, $canvas_elem_font_color, $ua);
      $offset += $canvas_elem_distance;
    }

    ### draw arrows
    my $last_timestamp = undef;
    my $y_offset = $canvas_margin + $canvas_pkg_distance;
    $i = 1;
    foreach my $packet(@{$packets}) {
      my $time_offset = defined $last_timestamp ? ($packet->timestamp->hires_epoch - $last_timestamp->hires_epoch) : 0;
      $last_timestamp = $packet->timestamp;
      my $from_x = $uas_pos_x{$packet->src_ip.':'.$packet->src_port};
      my $to_x = $uas_pos_x{$packet->dst_ip.':'.$packet->dst_port};
      #print "arrow from ".$packet->src_ip.':'.$packet->src_port." to ".$packet->dst_ip.':'.$packet->dst_port.": $from_x - $to_x\n";
      draw_arrow($canvas, $from_x, $y_offset, $to_x, $y_offset, $canvas_pkg_line_width,
      	$canvas_pkg_line_colors{$packet->transport} || $canvas_pkg_line_color);
      $packet->payload =~ /\ncseq:\s*(\d+)\s+[a-zA-Z]+/i;
      my $cseq = $1 ? $1 : '?';
      my $txt = sprintf($i.'. '.$packet->get_column('method').' ('.$cseq.', +%0.3fs)', $time_offset);
      my @bounds = $canvas->stringBounds($txt); # get bounds for text centering
      if($from_x < $to_x) {
        $from_x = $from_x+int($canvas_elem_distance/2)-int($bounds[0]/2);
      } elsif($from_x > $to_x) {
        $from_x = $from_x-int($canvas_elem_distance/2)-int($bounds[0]/2);
      } else {
        $from_x += 10; # call to itself, e.g. in cf loop
      }
      draw_text($canvas, $from_x, $y_offset-int(abs($bounds[1])/2), $canvas_pkg_font, $canvas_pkg_font_size, $canvas_pkg_font_color, $txt);

      push @{$r_info->{areas}}, {"id", $packet->id, "coords", ($from_x-$html_padding).','.($y_offset-abs($bounds[1])-$html_padding).','.($from_x+abs($bounds[0])+$html_padding).','.($y_offset)};

      $y_offset += $canvas_pkg_distance;
      ++$i;
    }
    $$r_png = $canvas->png;
}


sub generate_callmap {
    my $c = shift;
    my $packets = shift;
    my $png; my %info;
    process_callmap($c, $packets, \$png, \%info);
    return \%info;
}

sub generate_callmap_png {
    my $c = shift;
    my $packets = shift;
    my $png; my %info;
    process_callmap($c, $packets, \$png, \%info);
    return $png;    
}

1;
