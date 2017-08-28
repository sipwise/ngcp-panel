package NGCP::Panel::Form;
use Module::Load::Conditional qw/can_load/;

my %forms = ();

sub get {
    my ($name, $c) = @_;
    my $form;
    if(exists $forms{$name}) {
        $c->log->debug("++++ reuse form $name");
        $form = $forms{$name};
        $form->clear();
        $form->ctx($c);
    } else {
        $c->log->debug("++++ createe form $name");
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
