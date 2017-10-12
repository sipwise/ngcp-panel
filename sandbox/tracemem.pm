our $old = 0;
BEGIN {
    unshift @INC, sub {
        my ($self, $file) = @_;
        use GTop qw();
        my $current=GTop->new->proc_mem($$)->size;
        my $delta=$current-$old;
        printf "pid %d proc_mem %d delta %-10d file %s\n", $$, $current, $delta, $file;
        $old=$current;
    }
}
1;

# run with: perl -Isandbox -mtracemem ...
