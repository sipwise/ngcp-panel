package NGCP::Panel::Utils::Datatables;
use strict;
use warnings;

use Sipwise::Base;
use List::Util qw/first/;
use Scalar::Util qw/blessed/;
use DateTime::Format::Strptime;

sub process {
    my ($c, $rs, $cols, $row_func) = @_;

    my $use_rs_cb = ('CODE' eq (ref $rs));
    my $aaData = [];
    my $displayRecords = 0;


    # check if we need to join more tables
    # TODO: can we nest it deeper than once level?
    set_columns($c, $cols);
    unless ($use_rs_cb) {
        for my $col(@{ $cols }) {
            my @parts = split /\./, $col->{name};
            if($col->{literal_sql}) {
               $rs = $rs->search_rs(undef, {
                    '+select' => { '' => \[$col->{literal_sql}], -as => $col->{accessor} },
                    '+as' => [ $col->{accessor} ],
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
    #all joins already implemented, and filters aren't applied
    my $totalRecords = $use_rs_cb ? 0 : $rs->count;

    # generic searching
    my @searchColumns = ();
    my $searchString = $c->request->params->{sSearch} // "";
    foreach my $col(@{ $cols }) {
        # avoid amigious column names if we have the same column in different joined tables
        my $name = _get_joined_column_name_($col->{name});
        my $stmt; 
        if($col->{literal_sql}){
            #we can't use just accessor because of the count query
            $stmt = \[$col->{literal_sql} . " LIKE ?", [ {} => '%'.$searchString.'%'] ];
        }else{
            $stmt = { $name => { like => '%'.$searchString.'%' } };
        }
        push @searchColumns, $stmt if $col->{search};
    }
    if($searchString && ! $use_rs_cb) {
        $rs = $rs->search([@searchColumns]);
    }

    # data-range searching
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
    @searchColumns = ();
    foreach my $col(@{ $cols }) {
        # avoid amigious column names if we have the same column in different joined tables
        my $name = _get_joined_column_name_($col->{name});

        if($col->{search_from_epoch} && $from_date) {
            $rs = $rs->search({
                $name => { '>=' => $col->{search_use_datetime} ? $from_date_in : $from_date->epoch },
            });
        }
        if($col->{search_to_epoch} && $to_date) {
            $rs = $rs->search({
                $name => { '<=' => $col->{search_use_datetime} ? $to_date_in : $to_date->epoch },
            });
        }
    }
    $displayRecords = $use_rs_cb ? 0 : $rs->count;

    # show specific row on top (e.g. if we come back from a newly created entry)
    my $topId = $c->request->params->{iIdOnTop};
    if(defined $topId) {
        if(defined(my $row = $rs->find($topId))) {
            push @{ $aaData }, _prune_row($cols, $row->get_inflated_columns);
            if (defined $row_func) {
                $aaData->[-1]->put($row_func->($row));
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
            $aaData->[-1]->put($row_func->($row));
        }
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
