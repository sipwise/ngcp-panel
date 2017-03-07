#!/usr/bin/perl

use strict;

use Data::Dumper;
use NGCP::Schema;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use Test::More;
use Data::HAL qw();
use Data::HAL::Link qw();
use Safe::Isa qw($_isa);
use NGCP::Panel::Form::CFSimpleAPI;

my $schema = NGCP::Schema->connect();
my $ql_exists = 0;
my ($ql,$ana);

if($ql_exists){
    #use DBIx::Class::QueryLog;
    #use DBIx::Class::QueryLog::Analyzer;
    my $ql = DBIx::Class::QueryLog->new;
    $schema->storage->debugobj($ql);
    $schema->storage->debug(1);
    my $ana = DBIx::Class::QueryLog::Analyzer->new({ querylog => $ql });
    $ql->bucket('origin');
}

my $time = time();
print "start;\n";
#print Dumper($schema);

my $item_rs = $schema->resultset('voip_subscribers')->search( {
        'me.status' => { '!=' => 'terminated' }
    },{
        prefetch => { 'provisioning_voip_subscriber'=>'voip_cf_mappings'},
        #prefetch => 'provisioning_voip_subscriber',
        rows => 200,
    },
);
my (@arr_orig,@arr_opt);
for my $item ($item_rs->all) {
#       print Dumper({$item->get_inflated_columns});
    my %resource = ();
    my $prov_subs = $item->provisioning_voip_subscriber;
    for my $cf_type (qw/cfu cfb cft cfna cfs/) {
        my $mapping = $schema->resultset('voip_cf_mappings')->search({
                subscriber_id => $prov_subs->id,
                type => $cf_type,
            })->first;
        if ($mapping) {
            $resource{$cf_type} = _contents_from_cfm($mapping, $item);
        } else {
            $resource{$cf_type} = {};
        }
    }
    if(keys %{$resource{cft}}){
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => undef, attribute => 'ringtimeout', prov_subscriber => $prov_subs, schema => $schema )->first;
        $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;
        $resource{cft}{ringtimeout} = $ringtimeout_preference;
    }
    additional_processing($item, \%resource);
    push @arr_orig, \%resource;
}
print "1.time=".(time()-$time).";\n";
#exit;
if($ql_exists){
    $ql->bucket('optimized');
}
$time = time();

for my $item ($item_rs->all) {
    my %resource = ();
    my $prov_subs = $item->provisioning_voip_subscriber;
    @resource{qw/cfu cfb cft cfna cfs/} = ({}) x 5;
    for my $item_cf ($item->provisioning_voip_subscriber->voip_cf_mappings->all){
        $resource{$item_cf->type} = _contents_from_cfm($item_cf, $item);
    }
    if(keys %{$resource{cft}}){
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => undef, attribute => 'ringtimeout', prov_subscriber => $prov_subs, schema => $schema )->first;
        $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;
        $resource{cft}{ringtimeout} = $ringtimeout_preference;
    }
    additional_processing($item, \%resource);
    push @arr_opt, \%resource;
}
print "2.time=".(time()-$time).";\n";

is_deeply(\@arr_orig, \@arr_opt, "check that arrays are equiv");
#print Dumper[\@arr_orig, \@arr_opt];
if($ql_exists){
    print Dumper $ana->get_totaled_queries_by_bucket;
}






sub additional_processing{
    my($item,$resource) = @_;
    my $type='';
    my %resource=%$resource;
    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => 1,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", '')),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", '', $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
        ],
        relation => 'ngcp:callforwards',
    );
    my $form=NGCP::Panel::Form::CFSimpleAPI->new();

    validate_form(
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $hal->resource(\%resource);

}
sub _contents_from_cfm {
    my ($cfm_item, $sub) = @_;
    my (@times, @destinations);
    my $timeset_item = $cfm_item->time_set;
    my $dset_item = $cfm_item->destination_set;
    for my $time ($timeset_item ? $timeset_item->voip_cf_periods->all : () ) {
        push @times, {$time->get_inflated_columns};
        delete @{$times[-1]}{'time_set_id', 'id'};
    }
    for my $dest ($dset_item ? $dset_item->voip_cf_destinations->all : () ) {
        my ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($dest->destination);
        my $deflated;
        if($d eq "uri") {
            $deflated = NGCP::Panel::Utils::Subscriber::uri_deflate(undef, $duri,$sub) if $d eq "uri";
            $d = $dest->destination;
        }
        push @destinations, {$dest->get_inflated_columns,
                destination => $d,
                $deflated ? (simple_destination => $deflated) : (),
            };
        delete @{$destinations[-1]}{'destination_set_id', 'id'};
    }
    return {times => \@times, destinations => \@destinations};
}
sub validate_form {
    my (%params) = @_;

    my $resource = $params{resource};
    my $form = $params{form};
    my $run = $params{run} // 1;
    my $exceptions = $params{exceptions} // [];
    my $form_params = $params{form_params} // {};
    push @{ $exceptions }, "external_id";

    my @normalized = ();

    # move {xxx_id} into {xxx}{id} for FormHandler
    foreach my $key(keys %{ $resource } ) {
        my $skip_normalize = grep {/^$key$/} @{ $exceptions };
        if($key =~ /^(.+)_id$/ && !$skip_normalize && !exists $resource->{$1}) {
            push @normalized, $1;
            $resource->{$1}{id} = delete $resource->{$key};
        }
    }

    # remove unknown keys
    my %fields = map { $_->name => $_ } $form->fields;
    validate_fields($resource, \%fields, $run);

    if($run) {
        # check keys/vals
        $form->process(params => $resource, posted => 1, %{$form_params} );
        unless($form->validated) {
            my $e = join '; ', map { 
                sprintf 'field=\'%s\', input=\'%s\', errors=\'%s\'', 
                    ($_->parent->$_isa('HTML::FormHandler::Field') ? $_->parent->name . '_' : '') . $_->name,
                    $_->input // '',
                    join('', @{ $_->errors })
            } $form->error_fields;
            return;
        }
    }

    # move {xxx}{id} back into {xxx_id} for DB
    foreach my $key(@normalized) {
        next unless(exists $resource->{$key});
        $resource->{$key . '_id'} = defined($resource->{$key}{id}) ?
            int($resource->{$key}{id}) :
            $resource->{$key}{id};
        delete $resource->{$key};
    }

    return 1;
}

sub validate_fields {
    my ($resource, $fields, $run) = @_;
    
    for my $k (keys %{ $resource }) {
        #if($resource->{$k}->$_isa('JSON::XS::Boolean') || $resource->{$k}->$_isa('JSON::PP::Boolean')) {
        if($resource->{$k}->$_isa('JSON::PP::Boolean')) {
            $resource->{$k} = $resource->{$k} ? 1 : 0;
        }
        unless(exists $fields->{$k}) {
            delete $resource->{$k};
        }
        $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
            if $resource->{$k}->$_isa('DateTime');
        $resource->{$k} = $resource->{$k} + 0
            if(defined $resource->{$k} && (
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Integer') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Money') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Float')) &&
               (is_int($resource->{$k}) || is_decimal($resource->{$k})));

        if (defined $resource->{$k} &&
                $fields->{$k}->$_isa('HTML::FormHandler::Field::Repeatable') &&
                "ARRAY" eq ref $resource->{$k} ) {
            for my $elem (@{ $resource->{$k} }) {
                my ($subfield_instance) = $fields->{$k}->fields;
                my %subfields = map { $_->name => $_ } $subfield_instance->fields;
                validate_fields($elem, \%subfields, $run);
            }
        }

        # only do this for converting back from obj to hal
        # otherwise it breaks db fields with the \0 and \1 notation
        unless($run) {
            $resource->{$k} = $resource->{$k} ? JSON::true : JSON::false
                if(defined $resource->{$k} &&
                   $fields->{$k}->$_isa('HTML::FormHandler::Field::Boolean'));
        }
    }

    return 1;
}

1;
