package NGCP::Panel::Utils::MySQL;

sub bulk_insert {
	my(%params) = @_;
	my ($c, $s, $trans, $query, $data, $chunksize) = @params{qw/c schema do_transaction query data chunk_size/};
	my $guard;

	my $qparams = @{ $data->[0] };

	my $dbh = $s->storage->dbh;
	$guard = $s->txn_scope_guard if $trans;
	while(@{ $data }) {
		my @chunk = splice(@{ $data }, 0, $chunksize);
		my $q = $query . " VALUES " . join(",", ("(".join (",", (("?") x $qparams)).")") x @chunk );
		my $sth = $dbh->prepare($q);
		$sth->execute(map { @{ $_ } } @chunk);
		$sth->finish;
	}
	$guard->commit if $trans;

    return;
}

sub truncate_table {
	my(%params) = @_;
	my ($c, $s, $trans, $table) = @params{qw/c schema do_transaction table/};
	my $guard;

	my $dbh = $s->storage->dbh;
	$guard = $s->txn_scope_guard if $trans;
    my $q = 'TRUNCATE TABLE ' . $table;
	my $sth = $dbh->prepare($q);
    $sth->execute;
	$sth->finish;
	$guard->commit if $trans;

    return;
}

1;
