# this can be used to create a small in-memory but fully functional DBIx::Class schema
# to run some tests with internals of DBIC
use warnings;
use strict;
use DDP;

{
    package MyDB::ResultSet;
    use parent qw/DBIx::Class::Core/;
    1;
}

{
  package MyDB::Cd;
  use parent qw/DBIx::Class::Core/;
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->load_components("InflateColumn::DateTime", "Helper::Row::ToJSON");
  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/cdid title/);
  __PACKAGE__->set_primary_key('cdid');
  __PACKAGE__->has_many('tracks' => 'MyDB::Track');
  sub TO_JSON {
    my ($self) = @_;
    return {
        map { blessed($_) && $_->isa('DateTime') ? $_->datetime : $_ } %{ $self->next::method }
    };
}
  1;
}

{
  package MyDB::Track;
  use parent qw/DBIx::Class::Core/;
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->load_components("InflateColumn::DateTime", "Helper::Row::ToJSON");
  __PACKAGE__->table('track');
  __PACKAGE__->add_columns(qw/ trackid cd title/);
  __PACKAGE__->set_primary_key('trackid');
  __PACKAGE__->belongs_to('cd' => 'MyDB::Cd');
  sub TO_JSON {
    my ($self) = @_;
    return {
        map { blessed($_) && $_->isa('DateTime') ? $_->datetime : $_ } %{ $self->next::method }
    };
}
  1;
}

{
    package MyDB;
    # use Sipwise::Base '-skip'=>['TryCatch'];
    use parent qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(
        #result_namespace => 'MyDB',
        default_resultset_class => 'MyDB::ResultSet',);
    __PACKAGE__->load_classes(qw/Cd Track/);
    1;
}


#require MyDB;
my $s = MyDB->connect('dbi:SQLite:dbname=:memory:');

#p $s->deployment_statements;
$s->deploy({ add_drop_table => 1 });
my $r = $s->resultset("Track");
$r->create({trackid => 1, cd=>"Foo",title=>"bar"});
p $r->first;
#p $r;

p %INC;

<>;
exit 0;

# apt install cpanminus
# cpanm Module::Install SQL::Translator