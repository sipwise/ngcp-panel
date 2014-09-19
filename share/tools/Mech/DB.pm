package SQL;
use strict;
use DBI ();
use Data::Dumper;
my $log = Knetrix::Log->get_logger( LOG_DB );

=head1 sql_connect()

=head2 SYNOPSIS

  Useful wrapper for DBI->connect(). Generate DBI dsn string from current project config (use masterhost and masteruser parameters to connect to main project database and take there parameters for interested database) and pass it to DBI connect method. Handle DBI connect error.Set DB::Utility package dbh parameter
  Params:
    Main parameter - name of interested database. It can be passed as first sub parameter, or should be preset in package symbol table as db.
  Returns status of connecting to interested database.

=head2 USAGE

  Call from Knetrix::DB->instance

  $self->{db}         = $config{db};
  $self->sql_connect();
  

=cut

# sql_connect()
# Perform an SQL connect according to the chosen database
sub sql_connect {
    my $self = shift;
    my $db   = shift || $self->{db};

    $dbh = DBI->connect("DBI:".$cfg->{driver}."::$cfg->{host}",@$href{qw/user password/},
            { RaiseError  => 1,
             PrintError  => 1,
             PrintWarn   => 1,
             });
#             }) || throw Error::DBI($DBI::err,$DBI::errstr);
    $dbh->{HandleError} = \&_some_common_error_handler,
    $self->_dbh($dbh);
    $self->sql_select_db($db);
};#

=head1 sql_extern_connect()

=head2 SYNOPSIS

  Method makes DBI object from passed $host, $db, $user, $pass parameters. Generate dsn string, pass it to DBI->connect, handle errors, set DB::Utility package dbh parameter.
  Params:
    $host, $db, $user, $pass. $pass is optional, other are mandatory.
  Returns object of DBI.

=head2 USAGE

  Call from Knetrix::DB->instance

  $self->{db}         = $config{db};
  $self->sql_connect();

=cut

sub sql_extern_connect {
  my $self = shift;
  my ($host,$db,$user,$pass) = @_;
  my $dsn = $db ? "DBI:mysql:$db:$host" : $host;
  my $dbh = DBI->connect($dsn,$user,$pass,
			 { RaiseError=>1, PrintError=>1, PrintWarn=>1, }
			) || throw Knetrix::Error::DBI($DBI::err,$DBI::errstr);
  $dbh->{HandleError} = \&_error;
  $self->_dbh($dbh);
  return $dbh;
};#

=head1 _error()

=head2 SYNOPSIS

  Method makes all work around database error - rollback transaction, log error string to knetrix log and die with words of love to Fatherland.
  Params:
    Error string, package dbh parameter.
  Returns object of DBI.

=head2 USAGE

  Call from Knetrix::DB->instance

  $self->{db}         = $config{db};
  $self->sql_connect();

=cut

sub _error {
  my ($string,$dbh,$val) = @_;
  $dbh->rollback if ref $dbh eq 'DBI::dbh';
  #use Data::Dumper;
  #print STDERR Dumper [caller()];
  $log->logcluck("Database error: ",$string);
  die($string);
  #     throw Knetrix::Error::DBI->new($dbh->err,$string);
};#

=head1 _dbh()

=head2 SYNOPSIS

  Get/set dbi object.
  Params:
    if want set dbi object - then dbi object.
  Returns dbi object, if we get it.

=head2 USAGE

  $self->_dbh($dbh);

=cut

# _dbh : private
# get/set the dbi object
sub _dbh {
  my $self = shift;
  @_ ? $self->{_dbh} = shift : $self->{_dbh};
};#

# _trace : private
# set dbi trace level
sub _trace {
  shift->_dbh->trace(shift);
};#

sub fkey_off { shift->pexec("SET FOREIGN_KEY_CHECKS=0"); };#

sub fkey_on { shift->pexec("SET FOREIGN_KEY_CHECKS=1"); };#

# sql_select_db()
# Perform use command to select the database
# We also check to see whether we need a different database handle - Well one day
sub sql_select_db {
  my $self = shift;
  my $db = shift;
  $self->_dbh->do("use $db");
};#	

# sql_insert_id()
# Perform select last_insert_id()
sub sql_insert_id { shift->_dbh->selectrow_array("select last_insert_id()"); };#

# sql_rowcount()
# Perform an select found_rows() to find out the number of rows without limit x,y
sub sql_rowcount { shift->_dbh->selectrow_array("select found_rows()"); };#
sub sql_get_slock { shift->_dbh->selectrow_array("select get_lock(?,?)",undef,shift,shift); };#
sub sql_release_slock { shift->_dbh->do("select release_lock(?)",undef,shift); };#
sub sql_check_slock { shift->_dbh->selectrow_array("select is_free_lock(?)",undef,shift); };#

# quote()
# Perform a dbh_quote on a value
sub quote { shift->_dbh->quote(@_); };#

# pexec()
# Prepare and execute a statement
sub pexec {
  my ($self,$q,$ar_bind,$debug) = @_;
  no warnings;
  if($log->is_debug) {
    my $i = 0;
    (my $debug = $q) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  }

  my $dbh = $self->_dbh;
  my $sth = $dbh->prepare($q);
  $sth->execute(@$ar_bind);
  return $sth;
};#

sub sql_do {
  my ($self,$q,$ar_bind) = @_;
  if($log->is_debug) {
    my $i=0;
    ( my $debug = $q ) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  }
  $self->_dbh->do($q,undef,@$ar_bind);
};#

sub sql_get_def {
  my ($self,$table) = @_;
  ($self->_dbh->selectrow_array("show create table $table"))[1];
};#

## -------------------- INSERT --------------------
# sql_insert()
# Perform a SQL Insert or throw error if we have a problem
# ARG1 - string which looks like field1=?, field2=?
# ARG2 - arrayref of the bind variables for the vals string
sub sql_insert_row {
  my ($self,$table,$vals,$ar_bind,$ignore,$nodebug) = @_;
  my $dbh = $self->_dbh;
  my $q = "insert $ignore into $table set $vals";


  my $cfg = Knetrix::Config->get;
  if($cfg->dir_config('no_insert_set')){
    my ($f,$v) = ($vals,$vals);
		$f =~s/=[^,]+//g;
		$v =~s/,?\s*[^=]+\s*=\s*([^,]+)\s*(,|$)/$1$2/g;
		$q = "insert $ignore into $table($f) values ($v)";
		$log->debug($q);
  }

  no warnings;
  if($log->is_debug && !$nodebug) {
    my $i=0;
    ( my $debug = $q ) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  }
  my $ret = $dbh->do($q,undef,@$ar_bind);
};#

# sql_insert_multi()
# Perform a multiple set of inserts
# ARG1 - arrayref of hashes, each hash contains a 'vals' and 'bind' key with the values like ARG1, ARG2 of sql_insert()
sub sql_insert_multi {
  my ($self,$table,$aref) = @_;
  my $ret = 0;
  foreach my $href (@$aref) {
    my ($vals,$ar_bind) = @$href{qw/vals bind/};
    $ret += $self->sql_insert($table,$vals,$ar_bind);
  };
  $ret;
};#

# sql_insert_multimy()
# Perform a multiple set of inserts, using extended Mysql Syntax
# ARG1 - arrayref of hashes, each hash contains a 'vals' and 'bind' key with the values like ARG1, ARG2 of sql_insert()
sub sql_insert_multimy {
  my ($self,$table,$vals,$aref) = @_;
  my $bind;
  my $ins=substr('('.(substr('?,' x @{${$aref}[0]}, 0, -1).')') x @$aref, 0, -1);
  foreach my $href (@$aref) {
    push @$bind, @$href;
  };
  return $self->sql_insert($table,$vals.'values'.$ins,$bind);
};#

# sql_insertupdate_row()
# Perform a SQL Insert or throw error if we have a problem
# ARG1 - string which looks like field1=?, field2=?
# ARG2 - arrayref of the bind variables for the vals string
sub sql_insertupdate_row {
  my ($self,$table,$vals1,$vals2,$ar_bind,$ignore,$nodebug) = @_;
  my $dbh = $self->_dbh;
  if(!$vals2){
    $vals2 = $vals1;
    push @$ar_bind, @$ar_bind;
  }
  my $q = "insert $ignore into $table set $vals1 on duplicate key update $vals2";

  no warnings;
  if($log->is_debug && !$nodebug) {
    my $i=0;
    ( my $debug = $q ) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  }
  my $ret = $dbh->do($q,undef,@$ar_bind);
};#

## -------------------- SELECT --------------------
# sql_select_all()
# Perform a SQL select or throw an error if we have a problem
# ARG1 - If defined the value of this field forms the key in a return hash
# ARG2 - string which looks like field1=?, field2=?
# ARG3 - string which looks like where1=? AND where2=?
# ARG4 - arrayref of the bind variables for the field and where strings
sub sql_select_all {
  my $self = shift;	
  my ($table,$hash_id,$fields,$where,$ar_bind,$order,$group,$limit,$prefix) = @_;
  $log->error("No table") and return undef unless $table;
  my $dbh = $self->_dbh;
  $ar_bind ||= []; # Make sure $ar_bind exists
  $fields ||= "*";
  $where = "AND $where" if $where;
  $where .= " group by $group" if $group;
  $where .= " order by $order" if $order;
  $limit ||= "";
  if($limit) {
    $limit =~ s!\?!$self->quote(pop @$ar_bind,DBI::SQL_INTEGER)!ge;
  }
  my $query = "$prefix select $fields from $table where 1=1 $where $limit";
  if($log->is_debug) {
    my $i = 0;
    ( my $debug = $query ) =~ s!\?!$self->quote($ar_bind->[$i++])!ge;
    $Log::Log4perl::caller_depth = 1;
    $log->debug($debug);
    $Log::Log4perl::caller_depth = 0;
  }
  my $sth = $dbh->prepare($query);
  $sth->execute(@$ar_bind);
  return $hash_id ? $sth->fetchall_hashref($hash_id) :
		    $sth->fetchall_arrayref({});
};#

sub sql_select_union {
  my $self = shift;	
  my ($query,$hash_id,$ar_bind,$order,$group,$limit,$prefix) = @_;
  my $dbh = $self->_dbh;
  $ar_bind ||= []; # Make sure $ar_bind exists
  $order = " order by $order" if $order;
  $limit ||= "";
  if($limit) {
    $limit =~ s!\?!$self->quote(pop @$ar_bind,DBI::SQL_INTEGER)!ge;
  }
  $query = "$query $order $group $limit";
  if($log->is_debug) {
    my $i = 0;
    ( my $debug = $query ) =~ s!\?!$self->quote($ar_bind->[$i++])!ge;
    $Log::Log4perl::caller_depth = 1;
    $log->debug($debug);
    $Log::Log4perl::caller_depth = 0;
  }
  my $sth = $dbh->prepare($query);
  $sth->execute(@$ar_bind);
  return $hash_id ? $sth->fetchall_hashref($hash_id) :
		    $sth->fetchall_arrayref({});
};#

# sql_select_row()
# Perform a SQL select intended to return just one row.
# ARG1 - String which looks like field1,field2
# ARG2 - String which looks like where1=? AND where2=?
# ARG3 - Arrayref of the bind variables for the field and where strings
sub sql_select_row {
  my ($self,$table,$fields,$where,$ar_bind,$order,$group,$limit) = @_;
  my $dbh = $self->_dbh;
  $ar_bind ||=[]; # Make sure $ar_bind exists
  $where = "AND $where" if $where;
  $where .= " group by $group" if $group;
  $where .= " order by $order" if $order;
  $limit ||= "";
  my $query = "select $fields from $table where 1=1 $where $limit";
  if($log->is_debug) {
    my $i = 0;
    ( my $debug = $query ) =~ s!\?!$self->quote($ar_bind->[$i++])!ge;
    $log->debug($debug);
  }
	return $dbh->selectrow_hashref($query,undef,@$ar_bind);
};#

sub sql_select_col {
  my ($self,$table,$fields,$where,$ar_bind,$order,$group,$limit) = @_;
  my $dbh = $self->_dbh;
  $ar_bind ||=[];
  $where = "AND $where" if $where;
  $where .= " group by $group" if $group;
  $where .= " order by $order" if $order;
  $limit ||= "";
  my $query = "select $fields from $table where 1=1 $where $limit";
  if($log->is_debug) {
    my $i = 0;
    ( my $debug = $query ) =~ s!\?!$self->quote($ar_bind->[$i++])!ge;
    $log->debug($debug);
  }
  $dbh->selectrow_array($query,undef,@$ar_bind);
};#

## -------------------- DELETE --------------------
# sql_delete()
# Perform a SQL delete intended to remove a single row
# ARG1 - String which looks like where1=? AND where2=?
# ARG2 - Arrayref of the bind variables for the where string
sub sql_delete_row {
  my ($self,$table,$where,$ar_bind) = @_;
  my $dbh = $self->_dbh;
  if($log->is_debug) {
    my $query = "delete from $table where $where";
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $Log::Log4perl::caller_depth = 1;
    $log->debug($debug);
    $Log::Log4perl::caller_depth = 0;
  }
  $dbh->do("delete from $table where $where",undef,@$ar_bind);
};#    

#For multiple deleting
sub sql_delete_rows {
  my ($self,$table,$what,$where,$ar_bind) = @_;
  my $dbh = $self->_dbh;
  if($log->is_debug) {
    my $query = "delete $what from $table where $where";
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  }
  $dbh->do("delete $what from $table where $where",undef,@$ar_bind);
};#    

# sql_delete_ahref()
# Perform a set of SQL deletes based on an array of wheres and binds
# ARG1 - Arrayref of hashs with each containt a where string and arrayref of bind variables
sub sql_delete_aref {
  my ($self,$table,$aref) = @_;
  my $ret = 0;
  foreach my $href (@$aref) {
    my ($where,$ar_bind) = @$href{qw/where bind/};
    $ret += $self->sql_delete_row($table,$where,$ar_bind);
  }
  $ret;
};#

## -------------------- UPDATE --------------------
# sql_update()
# Perform an SQL update of a single row
# ARG1 - String which looks like field1=?, field2=?
# ARG2 - String which looks like where1=? AND where2=?
# ARG3 - Arrayref of bind variables for the set and where strings
sub sql_update_row {
  my ($self,$table,$set,$where,$ar_bind,%options) = @_;
  my $dbh = $self->_dbh;
  $where = "AND $where" if $where;
  my $query = "update $table set $set where 1=1 $where";
  if($log->is_debug) {
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug) unless $table eq 'session';
  }
  unless($options{test}) {
    my $ret = $dbh->do($query,undef,@$ar_bind);
    return $ret eq '0E0' ? 0 : $ret;
  }
};#

# sql_update_aahref()
# Updates a table using an aref of hrefs
# ARG1 - Arrayref of hashrefs, with each hashref containg the set & where strings and the arrayref of bind variables for these strings
sub sql_update_ahref {
  my ($self,$table,$aref) = @_;
  my $dbh = $self->_dbh;
  my $ret = 0;
  foreach my $hr (@$aref) {
    my ($set,$where,$ar_bind) = @$hr{qw/set where bind/};
    $ret += $self->sql_update_row($table,$set,$where,$ar_bind);
  }
  $ret;
};#

## -------------------- REPLACE --------------------
# sql_replace_row()
# Perform an SQL replace of a single row
# ARG1 - String which looks like field1=?, field2=?
# ARG2 - String which looks like where1=? AND where2=?
# ARG3 - Arrayref of bind variables for the set and where strings
sub sql_replace_row {
  my ($self,$table,$set,$ar_bind,$debug) = @_;
  my $dbh = $self->_dbh;
  my $query = "replace $table set $set";
  if($log->is_debug) {
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  };
  my $ret = $dbh->do($query,undef,@$ar_bind);
  return $ret eq '0E0' ? 0 : $ret;
};#



## -------------------- SELECT ROWS --------------------
# sql_do_selectall()
# Perform an SQL select of set of rows
# ARG1 - Sql statement
# ARG2 - Arrayref of bind variables for the set and where strings
# ARG3 - If defined the value of this field forms the key in a return hash
#why function exists? cause sometimes it is rather more simple to type and see all sql, but not from,what,where parts
########about range of arguments - ar_bind, hash_id - it is difference from sql_select_all, but rather often we dont need hash_id at all, so then we dont need write $sql,undef,[@values]
sub sql_do_selectall{
	my $self = shift;
	my ($query,$hash_id,$ar_bind) = @_;

	my $dbh = $self->_dbh;

	if($log->is_debug) {
		my $i = 0;
		( my $debug = $query ) =~ s!\?!$ar_bind->[$i++]!ge;
		$log->debug($debug);
	}
	my $sth = $dbh->prepare($query);
	$sth->execute(@$ar_bind);
	return $hash_id ? $sth->fetchall_hashref($hash_id) : $sth->fetchall_arrayref({});
}
## -------------------- SELECT ROW --------------------
# sql_do_selectrow()
# Perform an SQL replace of a single row
# ARG1 - Sql statement
# ARG2 - Arrayref of bind variables for the set and where strings
sub sql_do_selectrow {
  my $self = shift;
  my ($query,$ar_bind) = @_;
  my $dbh = $self->_dbh;
  if($log->is_debug) {
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  };
  return $dbh->selectrow_hashref($query,undef,@$ar_bind);
};#
## -------------------- SELECT COL --------------------
# sql_do_selectcol()
# Perform an SQL replace of a single row
# ARG1 - Sql statement
# ARG2 - Arrayref of bind variables for the set and where strings
sub sql_do_selectcol {
  my $self = shift;
  my ($query,$ar_bind) = @_;
  my $dbh = $self->_dbh;
  if($log->is_debug) {
    my $i=0;
    (my $debug = $query) =~ s!\?!$ar_bind->[$i++]!ge;
    $log->debug($debug);
  };
  return $dbh->selectrow_array($query,undef,@$ar_bind);
};#



1;
__END__
