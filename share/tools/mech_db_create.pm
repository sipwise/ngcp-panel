
$dbh->do('drop table urltemplate');
$dbh->do('drop table url');
$dbh->do('drop table urlcontent');
$dbh->do('drop table urlvariant');
$dbh->do('drop table control');
$dbh->do('drop table url_control');
$dbh->do('drop table url_template');
$dbh->do('create table urltemplate(id integer(11) auto_increment primary key, template varchar(512))');
$dbh->do('create table url(id integer(11) unsigned not null auto_increment primary key, url varchar(512), urltemplate_id integer(11), lastvisit timestamp default 0)');
$dbh->do('create table urlvariant(id integer(11) unsigned not null, url varchar(512), container_url_id integer(11))');
$dbh->do('create table urlcontent(id integer(11) unsigned not null, content text)');
$dbh->do('create table control(id integer(11) unsigned not null auto_increment primary key, label text, goto_url_id integer(11) unsigned)');
$dbh->do('create table url_control(url_id integer(11) unsigned, control_id integer(11) unsigned)');
$dbh->do('create table url_template(url_id integer(11) unsigned, urltemplate_id integer(11) unsigned)');
1;