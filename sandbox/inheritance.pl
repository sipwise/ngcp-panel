package Parent;

our $VERSION = 1.23;

sub VERSION { $VERSION }

sub child_version { $_[0]->VERSION }

package Child;
use base qw(Parent);

our $VERSION = 5.43;

sub VERSION { $VERSION }

sub new { bless {}, $_[0]; }

sub parent_version { $_[0]->SUPER::VERSION }


print "Child version is ", Child->VERSION, "\n";  # 5.43
my $child = Child->new;

print "Child version: ",  $child->VERSION, "\n";            # 5.43
print "Parent version: ", $child->parent_version, "\n"; # 1.23
print "Child version: ",  $child->child_version, "\n"; # 5.43