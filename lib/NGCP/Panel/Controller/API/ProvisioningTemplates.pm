package NGCP::Panel::Controller::API::ProvisioningTemplates;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ProvisioningTemplates qw();
use NGCP::Panel::Utils::DateTime qw();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Manage "provisioning templates" for creating subscribers with batch provisioning.';
};

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'name' => 'name',
        'lang' => 'lang',
    };
    return $cols;
}

sub query_params {
    return [
        {
            param => 'editable',
            description => 'Filter for editable provisioning templates',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ProvisioningTemplates/;

sub resource_name{
    return 'provisioningtemplates';
}

sub dispatch_path{
    return '/api/provisioningtemplates/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-provisioningtemplates';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub create_item {
    
    my ($self, $c, $resource, $form, $process_extras) = @_;
    
    $resource->{yaml} = NGCP::Panel::Utils::ProvisioningTemplates::dump_template($c,
        $resource->{id},
        $resource->{name},
        delete $resource->{template},
    );
    
    $resource->{id} = undef;
    $resource->{create_timestamp} = $resource->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                   
    my $item = $c->model('DB')->resultset('provisioning_templates')->create(
        $resource
    );
    
    return $item;

}

1;
