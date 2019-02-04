package NGCP::Panel::Controller::API::TimeSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::TimeSets/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
    PUT => { 
        'ContentType' => ['multipart/form-data'],#,
        'Uploads'    => {'calendar' => [NGCP::Panel::Utils::TimeSet::CALENDAR_MIME_TYPE]},
    },
    GET => {
        #first element of array is default, if no accept header was recieved.
        'ReturnContentType' => [NGCP::Panel::Utils::TimeSet::CALENDAR_MIME_TYPE,'application/json'],
    },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

sub get_item_binary_data{
    my($self, $c, $id, $item, $return_type) = @_;
    #caller waits for: $data_ref,$mime_type,$filename
    #while we will not strictly check Accepted header, if item can return only one type of the binary data
    my $extension = mime_type_to_extension($return_type);
    my $filename = NGCP::Panel::Utils::TimeSet::get_calendar_file_name(c => $c, timeset => $item ).'.'.$extension;
    my $data_ref = NGCP::Panel::Utils::TimeSet::get_timeset_icalendar(
        c       => $c,
        timeset => $c->stash->{'timeset_rs'},
    );
    $c->response->header('Content-Disposition' => 'attachment; filename="'..'"');
    return $data_ref, $return_type, $filename;
}

1;

# vim: set tabstop=4 expandtab:
