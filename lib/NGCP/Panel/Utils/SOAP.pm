package NGCP::Panel::Utils::SOAP;
use strict;
use warnings;

use SOAP::Lite;
use SOAP::WSDL::Expat::WSDLParser;
use SOAP::WSDL::XSD::Schema;
use XML::Simple;

use Exporter qw(import);
our @EXPORT = qw();
our @EXPORT_OK = qw(typed);
our %EXPORT_TAGS = qw();
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

sub typed;
sub dotype;

my $Parser = SOAP::WSDL::Expat::WSDLParser->new();
my %Wsdls;
my $Wsdl;
my $TNS;
my $TTNS;

### SOAP data typing function ###
sub typed {
  my $c = shift;
  my $response = shift;

  my $function = (caller(1))[3];
  $c->log->error("+++++ function=$function");
  return $response unless $function =~ /^Sipwise::(SOAP)::([^:]+)::([^:]+)$/;
  my $transport = $1;
  my $package = $2;
  $function = $3;

  $c->log->error("+++++ transport=$transport, package=$package, function=$function");

  my $WSDL = 'https://127.0.0.1:'. $c->config->{intercept}{soap_port} .'/SOAP/' . $package . '.wsdl';
  unless(exists $Wsdls{$package}) {
    $Wsdls{$package} = $Parser->parse_uri($WSDL);
  }

  $Wsdl = $Wsdls{$package};
  $TNS = $Wsdl->get_targetNamespace();
  $TTNS = ${${$Wsdl->get_types()}[0]->get_schema()}[-1]->get_targetNamespace();
  my $nss = ${${$Wsdl->get_types()}[0]->get_schema()}[-1]->get_xmlns();
  my $typens = 'typens';
  for(eval {keys %$nss}) {
    if($$nss{$_} eq $TTNS) {
      $typens = $_;
      last;
    }
  }

  my $resmsg = eval { ${$Wsdl->find_portType($TNS, $package.'PortType')->find_operation($TNS, $function)->get_output()}[0]->get_message()};
  return $response unless defined $resmsg;

  $resmsg =~ s/^.+://;

  if(defined ${$Wsdl->find_message($TNS, $resmsg)->get_part()}[0]) {
    my $resnam = ${$Wsdl->find_message($TNS, $resmsg)->get_part()}[0]->get_name();
    my $restyp = ${$Wsdl->find_message($TNS, $resmsg)->get_part()}[0]->get_type();
    if($restyp =~ /^$typens:/) {
      $response = dotype($resnam, $restyp, $response, $transport);
#      $response = SOAP::Data->name($resnam => $response);
    } else {
      $restyp =~ s/^(.+)://;
      $response = SOAP::Data->name($resnam => $response)->type($restyp);
    }
  } else { # "empty_Response" for void functions
    return $transport eq 'XMLRPC' ? undef : ();
  }

  return $response;
}

sub dotype {
  my ($resnam, $restyp, $response, $transport) = @_;
  my $tresponse;

  if($restyp =~ /^(.+):(.+)$/) {
    my $cns = $1;
    my $ctype = $2;
    if($ctype =~ s/Array$//) {
      $ctype =~ s/^String$/string/;
      if(eval { @$response }) {
        if($ctype eq 'boolean' or $ctype eq 'int' or $ctype eq 'string') {
          for(eval { @$response  }) {
            push @$tresponse, SOAP::Data->name(item => $_)->type($ctype);
          }
        } else {
          for(eval { @$response }) {
            push @$tresponse, dotype('item', "$cns:$ctype", $_, $transport);
          }
        }
        $tresponse = SOAP::Data->name($resnam => $tresponse);
      } else {
        if($ctype eq 'boolean' or $ctype eq 'int' or $ctype eq 'string') {
          $tresponse = SOAP::Data->name($resnam => [])->attr({'soapenc:arrayType' => "xsd:$ctype".'[0]'});
        } else {
          # FIXME: data types should be set to XMLRPC simple types for transport via XMLRPC
          # (because no other data types are known)
          # not fixed to avoid possible side-effects
          $tresponse = SOAP::Data->name($resnam => [])->attr({'soapenc:arrayType' => "$cns:$ctype".'[0]'});
        }
      }
    } elsif ($ctype =~ /Enum$/) {
      # set data types to string for transport via XMLRPC
      # (because the WSDL enum types are not known)
      if ($transport eq 'XMLRPC' || $ENV{HTTP_USER_AGENT} =~ /SOAP::Lite/i) {
        $tresponse = SOAP::Data->name($resnam => $response)->type('string');
      } else {
        $tresponse = SOAP::Data->name($resnam => $response)->type("$cns:$ctype");
      }
    } else {
      $restyp =~ s/^(.+)://;
      my $typdef = ${$Wsdl->get_types()}[0]->find_type($TTNS, $restyp);
      foreach my $telem (@{$typdef->get_element()}) {
        my $tnam = $telem->get_name();
        my $ttyp = $telem->get_type();
        $$tresponse{$tnam} = dotype($tnam, $ttyp, $$response{$tnam}, $transport);
      }
      # FIXME: data types should be set to XMLRPC simple types for transport via XMLRPC
      # (because no other data types are known)
      # not fixed to avoid possible side-effects
      $tresponse = SOAP::Data->name($resnam => $tresponse)->type("$cns:$restyp");
    }
  } else {
    # fix some types for trasport via XMLRPC
    # (because defaults are the SOAP types)
    if ($transport eq 'XMLRPC') {
        $restyp =~ s/^base64Binary$/base64/;
        $restyp =~ s/^float$/double/;

        # prevent "<int/>" in response for NULL values
        if ($restyp eq 'int' and not defined $response) {
          $response = 0;
        }
    }
    $tresponse = SOAP::Data->name($resnam => $response)->type($restyp);
  }

  return $tresponse;
}

1;
