package NGCP::Panel::Utils::Peering;
use NGCP::Panel::Utils::XMLDispatcher;

use strict;
use warnings;

sub _sip_lcr_reload {
    my(%params) = @_;
    my($c) = @params{qw/c/};
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>lcr.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

sub _sip_dispatcher_reload {
    my ($self, $c) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my ($res) = $dispatcher->dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>dispatcher.reload</methodName>
<params/>
</methodCall>
EOF

    return ref $res ? @{ $res } : ();
}

sub apply_rewrite {
    my (%params) = @_;

    my $c = $params{c};
    my $peer_host = $params{peer_host};
    my $callee = $params{number};
    my $dir = $params{direction};
    my $rws_id = $params{rws_id}; # override rewrite rule set
    my $rwr_rs = undef;

    return $callee unless $dir =~ /^(caller_in|callee_in|caller_out|callee_out|callee_lnp|caller_lnp)$/;

    my ($field, $direction) = split /_/, $dir;
    $dir = "rewrite_".$dir."_dpid";

    if ($rws_id) {
        $rwr_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    id => $rws_id,
                  }, {
                    '+select' => (sprintf "%s_%s_dpid", $field, $direction),
                    '+as' => qw(rwr_id),
                  });
        unless ($rwr_rs->count) {
            return $callee;
        }
    } elsif (not $peer_host) {
        $c->log->warn('could not apply rewrite: no peer host found.');
        return $callee;
    } else {
        $rwr_rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
            c => $c, attribute => $dir,
            peer_host => $peer_host,
        );
        unless($rwr_rs->count) {
            return $callee;
        }
    }

    my $rule_rs = $c->model('DB')->resultset('voip_rewrite_rules')->search({
        'ruleset.'.$field.'_'.$direction.'_dpid' =>
            $rws_id ? $rwr_rs->first->get_column('rwr_id')
                    : $rwr_rs->first->value,
        direction => $direction,
        field => $field,
    }, {
        join => 'ruleset',
        order_by => { -asc => 'priority' },
    });

    foreach my $r($rule_rs->all) {
        my $match = $r->match_pattern;
        my $replace = $r->replace_pattern;

        #print ">>>>>>>>>>> match=$match, replace=$replace\n";

        $match = [ $match ] if(ref $match ne "ARRAY");

        $replace = shift @{ $replace } if(ref $replace eq "ARRAY");
        $replace =~ s/\\(\d{1})/\${$1}/g;

        $replace =~ s/\"/\\"/g;
        $replace = qq{"$replace"};

        my $found;
        #print ">>>>>>>>>>> apply matches\n";
        foreach my $m(@{ $match }) {
            #print ">>>>>>>>>>>     m=$m, r=$replace\n";
            if($callee =~ s/$m/$replace/eeg) {
                # we only process one match
                #print ">>>>>>>>>>> match found, callee=$callee\n";
                $found = 1;
                last;
            }
        }
        last if $found;
        #print ">>>>>>>>>>> done, match=$match, replace=$replace, callee is $callee\n";
    }

    return $callee;
}

sub lookup {
    my (%params) = @_;

    my ($c, $caller, $callee, $prefix) = @{params}{qw(c caller callee prefix)};

    return unless $caller && $callee && $prefix;

    my $rs = $c->model('DB')->resultset('voip_peer_rules')->search({
        enabled => 1,
    },{
        '+columns' => {
                    rule_match => \do {
                        "'$prefix' LIKE CONCAT(callee_prefix,'%') as rule_match"
                    },
        },
        having => { rule_match => 1 },
        order_by => { -desc => qw/callee_prefix/ },
    });

    return undef unless $rs->first;

    my %peer_data;
    my @peer_groups;

    foreach my $rule ($rs->all) {
        my $caller_pattern = $rule->caller_pattern || '.*';
        my $callee_pattern = $rule->callee_pattern || '.*';
        next unless $caller =~ /$caller_pattern/;
        next unless $callee =~ /$callee_pattern/;
        push @{$peer_data{length($rule->callee_prefix)}{$rule->group->priority}}, $rule->group;
    }

    foreach my $len (sort { $b <=> $a } keys %peer_data) {
        my $len_data = $peer_data{$len};
        foreach my $prio (sort { $a <=> $b } keys %$len_data) {
            my $groups = $len_data->{$prio};
            foreach my $group (@$groups) {
                unless (grep { $_ eq $group} @peer_groups) {
                    push @peer_groups, $group;
                }
            }
        }
    }

    return \@peer_groups;
}


1;

=head1 NAME

NGCP::Panel::Utils::Peering

=head1 DESCRIPTION

A temporary helper to manipulate peerings related data

=head1 METHODS

=head2 _sip_lcr_reload

This is ported from ossbss.

Reloads lcr cache of sip proxies.

=head2 apply_rewrite

Applies rewrite rules using a peering group (and its first peering host preferences)

=head2 lookup

Peering group lookup based on peering rules and peering group priorities

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
