package NGCP::Panel::Form;

use warnings;
use strict;

use Module::Load::Conditional qw/can_load/;
use NGCP::Panel::Utils::I18N qw//;

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
        .( $create_new ? $create_new : "undefined" ).";");
    #$c->log->debug("Form requested: $name; exists: "
    #    .(exists $forms{$name})."; dont_use_cache: $dont_use_cache; own form cache config: "
    #    .(exists $forms{$name} && $forms{$name}->can('ngcp_no_cache') && $forms{$name}->ngcp_no_cache)."; create_new: "
    #    .( $create_new ? $create_new : "undefined" ).";");
    if( !$dont_use_cache
        && !$create_new
        && exists $forms{$name} 
        && !($forms{$name}->can('ngcp_no_cache') && $forms{$name}->ngcp_no_cache) 
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
        # translate form here to prevent multiple translations which leads to errors and doesn't work since the
        # source IDs (english) are no longer present
        NGCP::Panel::Utils::I18N->translate_form($c, $form);
    }
    return $form;
}

sub clear_form_cache {
    %forms = ();
}

1;
