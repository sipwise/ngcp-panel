package NGCP::Panel::Template::Plugin::DeviceConfig;

use warnings;
use strict;

use parent 'Template::Plugin';
use Crypt::RC4;

sub new {
	my ($class, $context) = @_;

	# set error via base ::error()
	# return $class->error("foo") if($foo)

	bless {
		_CONTEXT => $context,
	}, $class;	
}

sub innovaphone_pwdgen {
	my ($self, $user, $pass, $plain) = @_;
	my $key = $user;
	my $pad = 16 - (length $user) % 16;
	$key .= "\0" x $pad;
	$key .= $pass;
	$pad = 16 - (length $pass) % 16;
	$key .= "\0" x $pad;
	my $rc4 = Crypt::RC4->new($key);
	my $cipher = $rc4->RC4($plain);
	my $hexcipher = unpack("H*", $cipher);
	return $hexcipher;	
}

sub getValue {
  my $self = shift;
  foreach my $v(@_) {
    return $v if $v;
  }
  return;
}

sub getPref {
  my $self = shift;
  my ($pref_name, $default_val) = @_;

  my $preferences = $self->{_CONTEXT}->stash->get('preferences');
  if ($preferences) {
    foreach my $level (qw/device profile model/) {
      my $v = $preferences->{device}->{$level}->{$pref_name};
      next unless $v;
      return $v;
    }
  }

  return $default_val // '';
}

1;
