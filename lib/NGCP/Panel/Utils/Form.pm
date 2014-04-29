package NGCP::Panel::Utils::Form;

use Sipwise::Base;

sub validate_password {
    my %params = @_;
    my $c = $params{c};
    my $field = $params{field};
    my $r = $c->config->{security};
    my $pass = $field->value;

    if($r->{password_min_length} && length($pass) < $r->{password_min_length}) {
        $field->add_error($c->loc('Must be at minimum ' . $r->{password_min_length} . ' characters long'));
    }
    if($r->{password_max_length} && length($pass) > $r->{password_max_length}) {
        $field->add_error($c->loc('Must be at maximum ' . $r->{password_max_length} . ' characters long'));
    }
    if($r->{password_musthave_lowercase} && $pass !~ /[a-z]/) {
        $field->add_error($c->loc('Must contain lower-case characters'));
    }
    if($r->{password_musthave_uppercase} && $pass !~ /[A-Z]/) {
        $field->add_error($c->loc('Must contain upper-case characters'));
    }
    if($r->{password_musthave_digit} && $pass !~ /[0-9]/) {
        $field->add_error($c->loc('Must contain digits'));
    }
    if($r->{password_musthave_specialchar} && $pass !~ /[^0-9a-zA-Z]/) {
        $field->add_error($c->loc('Must contain special characters'));
    }
}


1;

# vim: set tabstop=4 expandtab:
