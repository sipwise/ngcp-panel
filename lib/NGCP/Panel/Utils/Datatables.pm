package NGCP::Panel::Utils::Datatables;
use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use List::Util qw/first/;
use Scalar::Util qw/blessed/;
use DateTime::Format::Strptime;

sub process {
    my ($c, $rs, $cols, $row_func, $total_row_func) = @_;

    my $use_rs_cb = ('CODE' eq (ref $rs));
    my $aaData = [];
    my $totalRecords = 0;
    my $displayRecords = 0;
    my $aggregate_cols = [];
    my $aggregations = {};


    # check if we need to join more tables
    # TODO: can we nest it deeper than once level?
    set_columns($c, $cols);
    unless ($use_rs_cb) {
        for my $col(@{ $cols }) {
            if ($col->{show_total}) {
                push @$aggregate_cols, $col;
            }
            my @parts = split /\./, $col->{name};
            if($col->{literal_sql}) {
                $rs = $rs->search_rs(undef, {
                    $col->{join} ? ( join => $col->{join} ) : (),
                    $col->{no_column} ? () : (
                        '+select' => { '' => \[$col->{literal_sql}], -as => $col->{accessor}  },
                        '+as' => [ $col->{accessor} ],
                    )
                });
            } elsif( @parts > 1 ) {
                my $join = $parts[$#parts-1];
                foreach my $table(reverse @parts[0..($#parts-2)]){
                    $join = { $table => $join };
                }
                $rs = $rs->search_rs(undef, {
                    join => $join,
                    '+select' => [ $parts[($#parts-1)].'.'.$parts[$#parts] ],
                    '+as' => [ $col->{accessor} ],
                });
            }
        }
    }
    #all joins already implemented, and filters aren't applied. But count we will take only if there are search and no other aggregations
    my $totalRecords_rs = $rs;
    #= $use_rs_cb ? 0 : $rs->count;
    
    ### Search processing section
    
    # generic searching
    my @searchColumns = ();
    #processing single search input - group1 from groups to be joined by 'AND'
    my $searchString = $c->request->params->{sSearch} // "";
    if($searchString && ! $use_rs_cb) {
    #for search string from one search input we need to check all columns which contain the 'search' spec (now: qw/search search_lower_column search_upper_column/). so, for example user entered into search input ip address - we don't know that it is ip address, so we check that name like search OR id like search OR search is between network_lower_value and network upper value 
        foreach my $col(@{ $cols }) {
            my ($name,$search_value,$op,$convert);
            # avoid amigious column names if we have the same column in different joined tables
            if($col->{search}){
                $op = (defined $col->{comparison_op} ? $col->{comparison_op} : 'like');
                $name = _get_joined_column_name_($col->{name});
                $search_value = (ref $col->{convert_code} eq 'CODE') ? $col->{convert_code}->($searchString) : '%'.$searchString.'%';
                my $stmt;
                if (defined $search_value) {
                    if($col->{literal_sql}){
                        if(!ref $col->{literal_sql}){
                            #we can't use just accessor because of the count query
                            $stmt = \[$col->{literal_sql} . " $op ?", [ {} => $search_value] ];
                        }else{
                            if($col->{literal_sql}->{format}){
                                $stmt = \[sprintf($col->{literal_sql}->{format}, " $op ?"), [ {} => $search_value] ];
                            }
                        }
                    }else{
                        $stmt = { $name => { $op => $search_value } };
                    }
                }
                if($stmt){
                    push @{$searchColumns[0]}, $stmt;
                }
            } elsif( $col->{search_lower_column} || $col->{search_upper_column} ) {
                my %conjunctSearchColumns = ();
                # searching lower and upper limit columns
                foreach my $search_spec (qw/search_lower_column search_upper_column/){
                    if ($col->{$search_spec}) {
                        $op = (defined $col->{comparison_op} ? $col->{comparison_op} : ( $search_spec eq 'search_lower_column' ? '<=' : '>=') );
                        $name = _get_joined_column_name_($col->{name});
                        $search_value = (ref $col->{convert_code} eq 'CODE') ? $col->{convert_code}->($searchString) : $searchString ;
                        if (defined $search_value) {
                            $conjunctSearchColumns{$col->{$search_spec}} = [] unless exists $conjunctSearchColumns{$col->{$search_spec}};
                            push(@{$conjunctSearchColumns{$col->{$search_spec}}},{$name => { $op => $search_value }});
                        }
                    }
                }
                foreach my $conjunct_column (keys %conjunctSearchColumns) {
                    #...things in arrays are OR'ed, and things in hashes are AND'ed

                    #input: 
#{ name => "billing_network_blocks._ipv4_net_from", search_lower_column => 'ipv4', convert_code => sub {
#    return _prepare_query_param_value(shift,4); # <================= this form of call, the same as all below, will return us bytes or undef
#    } },
#{ name => "billing_network_blocks._ipv4_net_to", search_upper_column => 'ipv4', convert_code => sub {
#    return _prepare_query_param_value(shift,4);
#    } },
#{ name => "billing_network_blocks._ipv6_net_from", search_lower_column => 'ipv6', convert_code => sub {
#    return _prepare_query_param_value(shift,6);
#    } },
#{ name => "billing_network_blocks._ipv6_net_to", search_upper_column => 'ipv6', convert_code => sub {
#    return _prepare_query_param_value(shift,6);
#    } },
                    #output: 
                    #1. conjunctSearchColumns = {
                        #'ipv4' => [
                            #{ "billing_network_blocks__ipv4_net_to"   => {"<=" => $bytes}}, 
                            #{ "billing_network_blocks__ipv4_net_from" => {"=>" => $bytes}}
                        #],
                        #'ipv6' => [
                            #{ "billing_network_blocks__ipv6_net_to"   => {"<=" => $bytes}}, 
                            #{ "billing_network_blocks__ipv6_net_from" => {"=>" => $bytes}}
                        #]
                    #}
                    #2. addition into @searchColumns = (
                        #{
                            #"billing_network_blocks__ipv4_net_to"   => {"<=" => $bytes},
                            #"billing_network_blocks__ipv4_net_from" => {"=>" => $bytes},
                        #},
                        #{
                            #"billing_network_blocks__ipv6_net_to"   => {"<=" => $bytes},
                            #"billing_network_blocks__ipv6_net_from" => {"=>" => $bytes},
                        #{
                    #)

                    push @{$searchColumns[0]}, { map { %{$_} } @{$conjunctSearchColumns{$conjunct_column}} };
                }
            }
        }
    }
    #/processing single search input
    #processing dates search input - group2 from groups to be joined by 'AND'
    {
        my @dateSearchColumns = ();
        # date-range searching
        my $from_date_in = $c->request->params->{sSearch_0} // "";
        my $to_date_in = $c->request->params->{sSearch_1} // "";
        my($from_date,$to_date);
        my $parser = DateTime::Format::Strptime->new(
            #pattern => '%Y-%m-%d %H:%M',
            pattern => '%Y-%m-%d',
        );
        if($from_date_in) {
            $from_date = $parser->parse_datetime($from_date_in);
        }
        if($to_date_in) {
            $to_date = $parser->parse_datetime($to_date_in);
        }
        foreach my $col(@{ $cols }) {
            # avoid amigious column names if we have the same column in different joined tables
            my $name = _get_joined_column_name_($col->{name});
            if($col->{search_from_epoch} && $from_date) {
                push @searchColumns, { $name => { '>=' => $col->{search_use_datetime} ? $from_date_in : $from_date->epoch } };
            }
            if($col->{search_to_epoch} && $to_date) {
                push @searchColumns, { $name => { '<=' => $col->{search_use_datetime} ? $to_date_in : $to_date->epoch } };
            }
        }
    }
    #/processing dates search input
    if(@searchColumns){
        $rs = $rs->search([@searchColumns]);
    }
    ### /Search processing section

    if(@$aggregate_cols){
        my(@select, @as);
        if(!$use_rs_cb){
            push @select, { 'count' => '*', '-as' => 'count' };
            push @as, 'count';
        }
        foreach my $col (@$aggregate_cols){
            my $col_accessor = $col->{literal_sql} ? \[ $col->{literal_sql} ] : $col->{accessor} ;#_get_joined_column_name_($col->{name});
            push @select, { $col->{show_total} => $col_accessor, '-as' => $col->{accessor} };
            push @as, $col->{accessor};
        }
        my $aggregate_rs = $rs->search_rs(undef,{
            'select' => \@select,
            'as' => \@as,
        });
        if(my $row = $aggregate_rs->first){
            if(!$use_rs_cb){
                $displayRecords = $row->get_column('count');
            }
            foreach my $col (@$aggregate_cols){
                $aggregations->{$col->{accessor}} = $row->get_column($col->{accessor});
            }
        }
    }
    if (defined $total_row_func && (scalar keys %{ $aggregate_cols }) > 0) {
        $aggregations = {%{$aggregations}, $total_row_func->($aggregations) };
    }

    if(!$use_rs_cb){
        if(@searchColumns){
            $totalRecords = $totalRecords_rs->count;
            if(!@$aggregate_cols){
                $displayRecords = $rs->count;
            }
        }else{
            if(@$aggregate_cols){
                $totalRecords = $displayRecords;
            }elsif(!@$aggregate_cols){
                $totalRecords = $displayRecords = $totalRecords_rs->count;
            }
        }
    }
    
    # show specific row on top (e.g. if we come back from a newly created entry)
    my $topId = $c->request->params->{iIdOnTop};
    if(defined $topId) {
        if(defined(my $row = $rs->find($topId))) {
            push @{ $aaData }, _prune_row($cols, $row->get_inflated_columns);
            if (defined $row_func) {
                $aaData->[-1] = {%{$aaData->[-1]}, $row_func->($row)};
            }
            $rs = $rs->search({ 'me.id' => { '!=', $topId} });
        }
    }

    # sorting
    my $sortColumn = $c->request->params->{iSortCol_0};
    my $sortDirection = $c->request->params->{sSortDir_0} || 'asc';
    if(defined $sortColumn && defined $sortDirection && ! $use_rs_cb) {
        if('desc' eq lc $sortDirection) {
            $sortDirection = 'desc';
        } else {
            $sortDirection = 'asc';
        }

        # first, get the fields we're actually showing
        my @displayedFields = ();
        for my $col(@{ $cols }) {
            next unless $col->{title};
            my $name = get_column_order_name($col);
            push @displayedFields, $name;
        }
        # ... and pick the name defined by the dt index
        my $sortName = $displayedFields[$sortColumn];

        $rs = $rs->search(undef, {
            order_by => {
                "-$sortDirection" => $sortName,
            }
        });
    }
    #/ sorting

    # pagination
    my $pageStart = $c->request->params->{iDisplayStart};
    my $pageSize = $c->request->params->{iDisplayLength};
    if ($use_rs_cb) {
        ($rs, $totalRecords, $displayRecords) = $rs->(
                offset       => $pageStart || 0,
                rows         => $pageSize  || 5,
                searchstring => $searchString,
            );
    } else {
        if(defined $pageStart && defined $pageSize && $pageSize > 0) {
            $rs = $rs->search(undef, {
                offset => $pageStart,
                rows => $pageSize,
            });
        }
    }

    for my $row ($rs->all) {
        push @{ $aaData }, _prune_row($cols, $row->get_inflated_columns);
        if (defined $row_func) {
            $aaData->[-1] = {%{$aaData->[-1]}, $row_func->($row)} ;
        }
    }

    if (keys %{ $aggregations }) {
        $c->stash(dt_custom_footer => $aggregations);
    }
    $c->stash(
        aaData               => $aaData,
        iTotalRecords        => $totalRecords,
        iTotalDisplayRecords => $displayRecords,
        sEcho                => int($c->request->params->{sEcho} // 1),
    );

}

sub set_columns {
    my ($c, $cols) = @_;

    for my $c(@{ $cols }) {
        next if defined $c->{accessor};
        $c->{accessor} = $c->{name};
        $c->{accessor} =~ s/\./_/g;
    }
    return $cols;
}

sub _prune_row {
    my ($columns, %row) = @_;
    while (my ($k,$v) = each %row) {
        unless (first { $_->{accessor} eq $k && $_->{title} } @{ $columns }) {
            delete $row{$k};
            next;
        }
        if(blessed($v) && $v->isa('DateTime')) {
            $row{$k} = $v->ymd('-') . ' ' . $v->hms(':');
            $row{$k} .= '.'.$v->millisecond if $v->millisecond > 0.0;
        }
    }
    return { %row };
}


sub get_column_order_name{
    my $col = shift;
    my $name;
    if($col->{literal_sql}){
        $name = $col->{accessor};
    }else{
        $name = _get_joined_column_name_($col->{name});
    }
    return $name;
}
sub _get_joined_column_name {
    my $cname = shift;
    my $name;
    if($cname !~ /\./) {
        if ($cname !~ /^v_(max|min|count)_/) {
            $name = 'me.'.$cname;
        } else { # virtual agrregated columns (count, min, max)
            $name = $cname;
        }
    } else {
        my @parts = split /\./, $cname;
        if(@parts == 2) {
            $name = $cname;
        } elsif(@parts == 3) {
            $name = $parts[1].'.'.$parts[2];
        } elsif(@parts == 4) {
            #I can suggest that in this case parts[1]may be  schema name. If it isn't, then it will be incorrect sql for example for order (and in other cases too). But I didn't see schema names usage in tt (at least accounting or billing). So, switched to new sub.
            $name = $parts[1].'.'.$parts[2].'.'.$parts[3];
        } else {
            # TODO throw an error for now as we only support one and two level
            $name = join('.',@parts[1 .. $#parts]);
        }
    }
    return $name;
}

sub _get_joined_column_name_{
    my $cname = shift;
    my $name;
    if($cname !~ /\./) {
        if ($cname !~ /^v_(max|min|count)_/) {
            $name = 'me.'.$cname;
        } else { # virtual agrregated columns (count, min, max)
            $name = $cname;
        }
    } else {
        my @parts = split /\./, $cname;
        if(@parts == 2){
            $name = $cname;
        }else{
            $name = join('.',@parts[($#parts-1) .. $#parts]);
        }
    }
    return $name;
}

1;


__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Utils::Datatables

=head1 DESCRIPTION

=head2 Format of Columns

Array with the following fields (preprocessed by set_columns):
    name: String
    search: Boolean
    search_from_epoch: Boolean
    search_to_epoch: Boolean
    title: String (Should be localized)
    show_total: String (if set, something like sum,max,...)


=head1 METHODS

=head2 C<process>

Query DB on datatables ajax request.

Format of the resultset callback (if used):
    Arguments as hash
    ARGUMENTS: offset, rows, searchstring
    RETURNS: ($rs, $totalcount, $displaycount)

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.


# vim: set tabstop=4 expandtab:
