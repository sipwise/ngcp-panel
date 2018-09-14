package NGCP::Panel::Utils::Datatables;
use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::Generic qw(:all);
use List::Util qw/first/;
use Scalar::Util qw/blessed/;

sub process {
    my ($c, $rs, $cols, $row_func, $params) = @_;

    $params //= {};
    my $total_row_func = $params->{total_row_func};
    my $use_rs_cb = ('CODE' eq (ref $rs));
    my $aaData = [];
    my $totalRecords = 0;
    my $displayRecords = 0;
    my $totalRecordCountClipped = 0;
    my $displayRecordCountClipped = 0;
    my $aggregate_cols = [];
    my $aggregations = {};

    my $user_tz = $c->session->{user_tz};


    # check if we need to join more tables
    # TODO: can we nest it deeper than once level?
    set_columns($c, $cols);
    my $totalRecords_rs = $rs;
    $rs = _resolve_joins($rs,$cols,$aggregate_cols) if (!$use_rs_cb);

    #all joins already implemented, and filters aren't applied. But count we will take only if there are search and no other aggregations
    #= $use_rs_cb ? 0 : $rs->count;

    ### Search processing section

    ($rs,my @searchColumns) = _apply_search_filters($c,$rs,$cols,$use_rs_cb);

    my $is_set_operations = 0;
    ($displayRecords, $displayRecordCountClipped, $is_set_operations) = _get_count_safe($c,$rs,$params) if(!$use_rs_cb);
    #my $footer = ((scalar @$aggregate_cols) > 0 and $displayRecordCountClipped);
    #$aggregate_cols = [] if $displayRecordCountClipped;
    if(@$aggregate_cols){
        unless ($displayRecordCountClipped or $displayRecords == 0) {
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
            if (defined $total_row_func) {
                $aggregations = {%{$aggregations}, $total_row_func->($aggregations) };
            }
        } else {
            foreach my $col (@$aggregate_cols){
                $aggregations->{$col->{accessor}} = '~';
            }
        }
    }


    if (!$use_rs_cb) {
        if (@searchColumns) {
            ($totalRecords, $totalRecordCountClipped) = _get_count_safe($c,$totalRecords_rs,$params);
        } else {
            ($totalRecords,$totalRecordCountClipped) = ($displayRecords,$displayRecordCountClipped);
        }
    }

    # show specific row on top (e.g. if we come back from a newly created entry)
    my $topId = $c->request->params->{iIdOnTop};
    if(defined $topId) {
        if(defined(my $row = $rs->find($topId))) {
            push @{ $aaData }, _prune_row($user_tz, $cols, $row->get_inflated_columns);
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
    my $searchString = $c->request->params->{sSearch} // "";
    my @rows = ();
    if ($use_rs_cb) {
        ($rs, $totalRecords, $displayRecords) = $rs->(
                offset       => $pageStart || 0,
                rows         => $pageSize  || 5,
                searchstring => $searchString,
            );
        @rows = $rs->all;
    } else {
        if($displayRecords > 0 and defined $pageStart and defined $pageSize and $pageSize > 0) {
            if ($is_set_operations and $displayRecordCountClipped) { # and defined $params->{count_limit} and $params->{count_limit} > 0) { #and $displayRecordCountClipped) {
                my ($stmt, @bind_vals) = @{${$totalRecords_rs->as_query}};
                ($is_set_operations,$stmt) = _limit_set_queries($stmt,sub {
                    my $part_stmt = shift;
                    return $part_stmt . ' limit ' . $params->{count_limit};
                });
                @bind_vals = map { $_->[1]; } @bind_vals;
                $c->log->debug("page stmt: " . $stmt);
                $c->log->debug("page stmt bind: " . join(",",@bind_vals));
                my $attrs = $totalRecords_rs->_resolved_attrs;
                $rs = $totalRecords_rs->result_source->resultset->search(undef, {
                   alias => $totalRecords_rs->current_source_alias,
                   from => [{
                      $totalRecords_rs->current_source_alias => \[ $stmt, @bind_vals ],
                      -alias                      => $totalRecords_rs->current_source_alias,
                      -source_handle              => $totalRecords_rs->result_source->handle,
                   }],
                   columns => $attrs->{as},
                   result_class => $rs->result_class,
                });
                $rs = _resolve_joins($rs,$cols);
            }
            $rs = $rs->search(undef, {
                offset => $pageStart,
                rows => $pageSize,
            });
            @rows = $rs->all;
        }
    }

    for my $row (@rows) {
        push @{ $aaData }, _prune_row($user_tz, $cols, $row->get_inflated_columns);
        if (defined $row_func) {
            $aaData->[-1] = {%{$aaData->[-1]}, $row_func->($row)} ;
        }
    }

    if (keys %{ $aggregations }) {
        $c->stash(dt_custom_footer => $aggregations);
    }

    add_arbitrary_data($c, $aaData, $params->{topData}, $cols, $row_func, $params);

    expose_data($c, $aaData, $totalRecords, $totalRecordCountClipped, $displayRecords, $displayRecordCountClipped);

}

sub apply_dt_joins_filters {
    my ($c,$rs, $cols) = @_;
    $rs = _resolve_joins($rs, $cols, undef, 1, 1);
    ($rs,my @searchColumns) = _apply_search_filters($c,$rs,$cols);
    return $rs;
}

sub _resolve_joins {

    my ($rs, $cols, $aggregate_cols, $skip_aggregates,$join_only) = @_;
    for my $col(@{ $cols }) {
        if ($col->{show_total}) {
            push(@$aggregate_cols, $col) if defined $aggregate_cols;
            next if $skip_aggregates;
        }
        my @parts = split /\./, $col->{name};
        if($col->{literal_sql}) {
            $rs = $rs->search_rs(undef, {
                $col->{join} ? ( join => $col->{join} ) : (),
                ($col->{no_column} or $join_only) ? () : (
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
                ($join_only ? () : ('+select' => [ $parts[($#parts-1)].'.'.$parts[$#parts] ],
                '+as' => [ $col->{accessor} ],)),
            });
        }
    }
    return $rs;

}

sub _apply_search_filters {

    my ($c,$rs,$cols,$use_rs_cb) = @_;
    # generic searching
    my @searchColumns = ();
    my %conjunctSearchColumns = ();
    #processing single search input - group1 from groups to be joined by 'AND'
    my $searchString = $c->request->params->{sSearch} // "";
    if ($searchString && !$use_rs_cb) {
    #for search string from one search input we need to check all columns which contain the 'search' spec (now: qw/search search_lower_column search_upper_column/). so, for example user entered into search input ip address - we don't know that it is ip address, so we check that name like search OR id like search OR search is between network_lower_value and network upper value
        foreach my $col(@{ $cols }) {
            my ($name,$search_value,$op,$convert);
            # avoid amigious column names if we have the same column in different joined tables
            if($col->{search} or $col->{strict_search} or $col->{int_search}){
                my $is_pattern = 0;
                my $searchString_escaped = join('',map {
                    my $token = $_;
                    if ($token ne '\\\\') {
                        $token =~ s/%/\\%/g;
                        $token =~ s/_/\\_/g;
                        if ($token =~ s/(?<!\\)\*/%/g) {
                            $is_pattern = 1;
                        }
                        $token =~ s/\\\*/*/g;
                    }
                    $token;
                } split(/(\\\\)/,$searchString,-1));
                if ($is_pattern) {
                    $op = 'like';
                    $search_value = $searchString_escaped;
                } elsif ($col->{strict_search}) {
                    $op = '=';
                    $searchString_escaped = $searchString;
                    $searchString_escaped =~ s/\\\*/*/g;
                    $searchString_escaped =~ s/\\\\/\\/g;
                    $search_value = $searchString_escaped;
                } elsif ($col->{int_search}) {
                    $op = '=';
                    $search_value = $searchString;
                } else {
                    $op = 'like';
                    $search_value = '%' . $searchString_escaped . '%';
                }
                $name = _get_joined_column_name_($col->{name});
                $op = $col->{comparison_op} if (defined $col->{comparison_op});
                $search_value = $col->{convert_code}->($searchString) if (ref $col->{convert_code} eq 'CODE');
                my $stmt;
                if (defined $search_value) {
                    if ($col->{literal_sql}) {
                        if (!ref $col->{literal_sql}) {
                            #we can't use just accessor because of the count query
                            $stmt = \[$col->{literal_sql} . " $op ?", [ {} => $search_value] ];
                        } else {
                            if ($col->{literal_sql}->{format}) {
                                $stmt = \[sprintf($col->{literal_sql}->{format}, " $op ?"), [ {} => $search_value] ];
                            }
                        }
                    } elsif (not $col->{int_search} or $searchString =~ /^\d{1,10}$/) {
                        $stmt = { $name => { $op => $search_value } };
                    }
                }
                if ($stmt) {
                    push @{$searchColumns[0]}, $stmt;
                }
            } elsif ( $col->{search_lower_column} || $col->{search_upper_column} ) {
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
            }
        }
        foreach my $conjunct_column (keys %conjunctSearchColumns) {
            #...things in arrays are OR'ed, and things in hashes are AND'ed
            push @{$searchColumns[0]}, { map { %{$_} } @{$conjunctSearchColumns{$conjunct_column}} };
        }
    }
    #/processing single search input
    #processing dates search input - group2 from groups to be joined by 'AND'
    {
        # date-range searching
        my $from_date_in = $c->request->params->{sSearch_0} // "";
        my $to_date_in = $c->request->params->{sSearch_1} // "";
        my($from_date,$to_date);
        if($from_date_in) {
            $from_date = NGCP::Panel::Utils::DateTime::from_forminput_string($from_date_in, $c->session->{user_tz});
        }
        if($to_date_in) {
            $to_date = NGCP::Panel::Utils::DateTime::from_forminput_string($to_date_in, $c->session->{user_tz});
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
        $rs = $rs->search_rs({
                "-and" => [@searchColumns],
            });
    }
    ### /Search processing section

    return ($rs,@searchColumns);

}

sub _get_count_safe {
    my ($c,$rs,$params) = @_;
    my $count_limit = $params->{count_limit};
    #$count_limit = 12;
    my $is_set_operations;
    if ($c and defined $count_limit and $count_limit > 0) {
        #use Data::Dumper;
        #$c->log->debug("count_limit: $count_limit " . Dumper($params));
        my ($count_clipped) = $c->model('DB')->storage->dbh_do(sub {
            my ($storage, $dbh, $stmt, @bind_vals) = @_;
            $c->log->debug("entered dbdo");
            ($is_set_operations,$stmt) = _limit_set_queries($stmt,sub {
                my $part_stmt = shift;
                return $part_stmt . ' limit ' . ($count_limit + 1);
            });
            @bind_vals = map { $_->[1]; } @bind_vals;
            $c->log->debug("count stmt: " . "select count(1) from ($stmt) as query_clipped");
            $c->log->debug("count stmt bind: " . join(",",@bind_vals));
            return $dbh->selectrow_array("select count(1) from ($stmt) as query_clipped",undef,@bind_vals);
        },@{${$rs->search_rs(undef,{
            page => 1,
            rows => ($count_limit + 1),
            #below is required if fields with identical name are selected by $rs:
            'select' => (defined $params->{count_projection_column} ? $params->{count_projection_column} : \"1"),
            #select => $rs->_resolved_attrs->{select},
            #as => $rs->_resolved_attrs->{as},
        })->as_query}});
        if ($count_clipped > $count_limit) {
            $c->log->debug("result count clipped");
            return ($count_limit,1,$is_set_operations);
        } else {
            $c->log->debug("result count not clipped");
            return ($count_clipped,0,$is_set_operations);
        }
    } else {
        return ($rs->count,0,$is_set_operations);
    }
}

sub add_arbitrary_data {
    my ($c, $aaData, $topData, $cols, $row_func, $params) = @_;
    # show any arbitrary data rows on top, just like a union would do
    # hash is expected or array of hashes expected
    my $user_tz = $params->{user_tz} // $c->session->{user_tz};
    if (defined $topData) {
        my $topDataArray;
        if (ref $topData eq 'HASH') {
            $topDataArray = [$topData];
        } else {
            $topDataArray = $topData;
        }
        foreach my $topDataRow (@$topDataArray) {
            unshift @{ $aaData }, _prune_row($user_tz, $cols, %$topDataRow);
            if (defined $row_func) {
                $aaData->[0] = {%{$aaData->[0]}, $row_func->($topDataRow)};
            }
        }
    }
}

sub expose_data {
    my($c, $aaData, $totalRecords, $totalRecordCountClipped, $displayRecords, $displayRecordCountClipped) = @_;
    $c->stash(
        aaData               => $aaData,
        iTotalRecords        => $totalRecords,
        iTotalDisplayRecords => $displayRecords,
        iTotalRecordCountClipped        => ($totalRecordCountClipped ? \1 : \0),
        iTotalDisplayRecordCountClipped => ($displayRecordCountClipped ? \1 : \0),
        sEcho                => int($c->request->params->{sEcho} // 1),
    );
}

sub process_static_data {
    my ($c, $data, $cols, $row_func, $params) = @_;
    $params //= {};

    foreach my $field (qw/total_row_func/) {
        #todo: error here about unsupported functionality
    }

    my $aaData = [];
    add_arbitrary_data($c, $aaData, $data, $cols, $row_func, $params);
    my $totalRecords = scalar @$aaData;
    my $displayRecords = $totalRecords;
    expose_data($c, $aaData, $totalRecords, 0, $displayRecords, 0);
}

sub set_columns {
    my ($c, $cols) = @_;

    for my $col(@{ $cols }) {
        next if defined $col->{accessor};
        $col->{accessor} = $col->{name};
        $col->{accessor} =~ s/\./_/g;
    }
    return $cols;
}

sub _prune_row {
    my ($user_tz, $columns, %row) = @_;
    while (my ($k,$v) = each %row) {
        unless (first { $_->{accessor} eq $k && $_->{title} } @{ $columns }) {
            delete $row{$k};
            next;
        }
        if(blessed($v) && $v->isa('DateTime')) {
            if($user_tz) {
                $v->set_time_zone('local');  # starting point for conversion
                $v->set_time_zone($user_tz);  # desired time zone
            }
            $row{$k} = $v->ymd('-') . ' ' . $v->hms(':');
            $row{$k} .= '.'.sprintf("%03d",$v->millisecond) if $v->millisecond > 0.0;
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

sub _limit_set_queries {
    my ($stmt,$sub) = @_;
    return (undef,$stmt) unless $sub;
    #simple lexer for parsing sql stmts with a single level of set operations.
    #caveat: set operator names must not appear in colnames, table names, literals etc.
    my $set_operation_re = "union\\s+distinct|union\\s+all|union|intersect|except";
    my @frags = split(/\s($set_operation_re)\s/i,$stmt, -1);
    return (0,$stmt) unless (scalar @frags) > 1;
    my @frags_rebuilt = ();

    my ($preamble,$postamble) = (undef,undef);
    foreach my $frag (@frags) {
        if ($frag =~ /($set_operation_re)/i) {
            push(@frags_rebuilt,$1);
        } else {
            my $set_stmt = $frag;
            $set_stmt =~ s/\s+$//g;
            $set_stmt =~ s/^\s+//g;
            my $last = (((scalar @frags) - (scalar @frags_rebuilt)) == 1 ? 1 : 0);
            my $first = ((scalar @frags_rebuilt) == 0 ? 1 : 0);
            my $quoted = 0;
            my $depth = 0;
            my ($left_parenthesis_count,$right_parenthesis_count) = (0,0);
            my $rebuilt = '';
            my $balanced;
            if ($last) {
                for (my $i = 0; $i < length($set_stmt); $i++) {
                    my $char = substr($set_stmt, $i, 1);
                    my $escape = substr($set_stmt, $i, 2);
                    if ($escape eq '\\\\' or $escape eq '\\"' or $escape eq "\\'") {
                        $rebuilt .= $escape;
                        $i++;
                    } else {
                        if ($char eq "'" or $char eq '"') {
                            $quoted = ($quoted ? 0 : 1);
                        } elsif (not $quoted and $char eq ')') {
                            last if ($depth == 0);
                            $depth--;
                            $right_parenthesis_count++;
                        } elsif (not $quoted and $char eq '(') {
                            $depth++;
                            $left_parenthesis_count++;
                        }
                        $rebuilt .= $char;
                    }
                    if ($left_parenthesis_count == $right_parenthesis_count and $depth == 0) {
                        $balanced = $rebuilt;
                    }
                }
                $postamble = substr($set_stmt,length($balanced));
            } else {
                for (my $i = length($set_stmt) - 1; $i >= 0; $i--) {
                    my $char = substr($set_stmt, $i, 1);
                    my $escape = substr($set_stmt, $i - 1, 2);
                    if ($escape eq '\\\\' or $escape eq '\\"' or $escape eq "\\'") {
                        $rebuilt = $escape . $rebuilt;
                        $i--;
                    } else {
                        if ($char eq "'" or $char eq '"') {
                            $quoted = ($quoted ? 0 : 1);
                        } elsif (not $quoted and $char eq ')') {
                            $depth--;
                            $right_parenthesis_count++;
                        } elsif (not $quoted and $char eq '(') {
                            $depth++;
                            $left_parenthesis_count++;
                        }
                        $rebuilt = $char . $rebuilt;
                    }
                    if ($left_parenthesis_count == $right_parenthesis_count and $depth == 0) {
                        $balanced = $rebuilt;
                        last if ($first and not $quoted and 'select' eq lc(substr($rebuilt,0,6)));
                    }
                }
                if ($first) {
                    $preamble = substr($set_stmt,0, length($set_stmt) - length($balanced));
                }
            }
            #normalize outer parentheses for easier handling in $sub:
            while ($balanced =~ /^\s*\(\s*/g and $balanced =~ /\s*\)\s*$/g) {
                $balanced =~ s/^\s*\(\s*//g;
                $balanced =~ s/\s*\)\s*$//g;
            }
            $balanced = &$sub($balanced);
            push(@frags_rebuilt,'(' . $balanced . ')');
        }
    }
    unshift(@frags_rebuilt,$preamble) if $preamble;
    push(@frags_rebuilt,$postamble) if $postamble;

    #my $i=0;
    #print(join("\n",map { $i++;$i.'. '.$_; } @frags_rebuilt));
    return (1,join(' ',@frags_rebuilt));

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
