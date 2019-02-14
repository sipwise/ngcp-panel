package NGCP::Panel::Form;
use Module::Load::Conditional qw/can_load/;

my %forms = ();
our $dont_use_cache = 0;

sub dont_use_cache {
    if (scalar @_){
        $dont_use_cache = $_[0];
    }
    return $dont_use_cache;
}

sub get {
    my ($name, $c, $create_new) = @_;
    my $form;
    $c->log->debug("Form requested: $name; dont_use_cache: $dont_use_cache; create_new: "
        .( $create_new // "undefined" ).";");
    if( !$dont_use_cache
        && !$create_new
        && exists $forms{$name} 
    ) {
        $c->log->debug("form is taken from cache");
        $form = $forms{$name};
        $form->clear();
        $form->ctx($c);
        $form->setup_form();
    } else {
        my $use_list = { $name => undef };
        unless(can_load(modules => $use_list, nocache => 0, autoload => 0)) {
            $c->log->error("Failed to load module $name: ".$Module::Load::Conditional::ERROR."\n");
            return;
        }
        $form = $forms{$name} = $name->new(ctx => $c);
    }
    return $form;
}

1;
