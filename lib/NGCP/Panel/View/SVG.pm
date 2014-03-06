package NGCP::Panel::View::SVG;

use Sipwise::Base;
use NGCP::Panel::Utils::I18N;

use strict;
extends 'Catalyst::View::TT';


__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    WRAPPER => '',
    FILTERS => {},
    ABSOLUTE => 0,
    expose_methods => [],
);

sub process
{
    my ( $self, $c ) = @_;
    #$c->res->content_type("image/svg+xml");


    if($c->stash->{VIEW_NO_TT_PROCESS}) {
        $c->log->debug("VIEW_NO_TT_PROCESS=".$c->stash->{VIEW_NO_TT_PROCESS}.";\n");
        
        my $output = $self->getTemplateContent($c);

        $c->log->debug("output is empty=".($output?0:1).";\n");
        
        $c->response->body($output);
        #$self->{template}->{LOAD_TEMPLATES}->load();
    } else{
        $c->log->debug("VIEW INVOICE TEMPLATE:just send to process;\n");
        $self->SUPER::process($c) ;
    }
    return 1;
}
sub getTemplate{
    my ( $self, $c, $template ) = @_;
    if(defined $template){
        $c->log->debug("getTemplate: template=$template;");
    }
    $template ||= ( $c->stash->{template} ||  $c->action . $self->config->{TEMPLATE_EXTENSION} );
    $c->log->debug("getTemplate: template=$template;");
    return $template;
}
#method is necessary to apply APP specific template configurations, e.g. path, tt file extensions etc
#may be moved to main view class, but as on template_invoice experiments stage it would be ok to leave it in separated class
sub getTemplateContent{
    my ( $self, $c, $template ) = @_;
    
    return $self->{template}->context->insert($self->getTemplate($c,$template));
}
sub getTemplateProcessed{
    my ( $self, $c, $template ) = @_;
    
    return $self->{template}->context->process($self->getTemplate($c,$template));
}

1;