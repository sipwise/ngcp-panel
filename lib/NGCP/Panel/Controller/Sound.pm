package NGCP::Panel::Controller::Sound;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::SoundSet;
use NGCP::Panel::Form::SoundFile;
use File::Type;
use IPC::System::Simple qw/capturex/;
use NGCP::Panel::Utils::XMLDispatcher;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub sets_list :Chained('/') :PathPart('sound') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $sets_rs = $c->model('provisioning')->resultset('voip_sound_sets');
    $c->stash(sets_rs => $sets_rs);

    $c->stash(has_edit => 1);
    $c->stash(has_delete => 1);
    $c->stash(template => 'sound/list.tt');
}

sub root :Chained('sets_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('sets_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{sets_rs};
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "name", "description"],
                 [1,2]]);
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('sets_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && $set_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid Sound Set id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{sets_rs}->find($set_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Sound Set does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    $c->stash(set_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::SoundSet->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/sound/edit'),
        item   => $c->stash->{set_result},
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Sound Set successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{set_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Sound Set successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->uri_for());
}

sub create :Chained('sets_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::SoundSet->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/sound/create'),
        item   => $c->stash->{sets_rs}->new_result({}),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Sound Set successfully created!'}]);
        $c->response->redirect($c->uri_for_action('/sound/root'));
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub handles_list :Chained('base') :PathPart('handles') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $files_rs = $c->stash->{set_result}->voip_sound_files;
    $c->stash(files_rs => $files_rs);
    $c->stash(handles_base_uri =>
        $c->uri_for_action("/sound/handles_root", [$c->req->captures->[0]]));
    
    my $handles_rs = $c->model('provisioning')->resultset('voip_sound_groups')
        ->search({
        },{
            select => ['groups.name', \'handles.name', \'handles.id', 'files.filename', 'files.loopplay', 'files.codec'],
            as => [ 'groupname', 'handlename', 'handleid', 'filename', 'loopplay', 'codec'],
            alias => 'groups',
            from => [
                { groups => 'voip_sound_groups' },
                [
                    { handles => 'voip_sound_handles', -join_type=>'left'},
                    { 'groups.id' => 'handles.group_id'},
                ],
                [
                    { files => 'voip_sound_files', -join_type => 'left'},
                    { 'handles.id' => { '=' => \'files.handle_id'}, 'files.set_id' => $c->stash->{set_result}->id},
                ],
            ],
        });
    
    my @rows = $handles_rs->all;
    
    my %groups;
    for my $handle (@rows) {
        $groups{ $handle->get_column('groupname') } = []
            unless exists $groups{ $handle->get_column('groupname') };
        push $groups{ $handle->get_column('groupname') }, $handle;
    }
    $c->stash(sound_groups => \%groups);

    $c->stash(has_edit => 1);
    $c->stash(has_delete => 1);
    $c->stash(template => 'sound/handles_list.tt');
}

sub handles_root :Chained('handles_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub handles_base :Chained('handles_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $handle_id) = @_;

    unless($handle_id && $handle_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid Sound Handle id detected!'}]);
        $c->response->redirect($c->stash->{handles_base_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{files_rs}->find_or_new(handle_id => $handle_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Sound File could not be found/created!'}]);
        $c->response->redirect($c->stash->{handles_base_uri});
        $c->detach;
        return;
    }
    $c->stash(file_result => $res);
}

sub handles_edit :Chained('handles_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $upload = $c->req->upload('soundfile');
    my %params = (
        %{ $c->request->params },
        soundfile => $posted ? $upload : undef,
    );
    my $file_result = $c->stash->{file_result};
    my $form = NGCP::Panel::Form::SoundFile->new;
    $form->process(
        posted => $posted,
        params => \%params,
        item   => $file_result,
    );
    
    if($form->validated) {
        if (defined $upload) {
            my $soundfile = eval { $upload->slurp };
            my $filename = eval { $upload->filename };
            
            my $ft = File::Type->new();
            unless ($ft->checktype_contents($soundfile) eq 'audio/x-wav') {
                $c->flash(messages => [{type => 'error', text => 'Invalid File Type detected!'}]);
                $c->response->redirect($c->stash->{handles_base_uri});
                return;
            }
            
            my $target_codec = 'WAV';
            
            if($file_result->handle->group->name eq 'calling_card') {
                try {
                    $self->_clear_audio_cache($file_result->set_id, $file_result->handle->name);
                } catch ($e) {
                    $c->flash(messages => [{type => 'error', text => 'Failed to clear audio cache!'}]);
                    $c->response->redirect($c->stash->{handles_base_uri});
                    return;
                }
            }

            if ($file_result->handle->name eq 'music_on_hold') {
                $target_codec = 'PCMA';
                $filename =~ s/\.[^.]+$/.pcma/;
            }

            try {
                $soundfile = $self->_transcode_sound_file(
                    $upload->tempname, 'WAV', $target_codec);
            } catch ($error) {
                $c->flash(messages => [{type => 'error', text => 'Transcode of audio file failed!'}]);
                $c->log->info("Transcode failed: $error");
                $c->response->redirect($c->stash->{handles_base_uri});
                return;
            }
            
            $file_result->update({
                filename => $filename,
                data => $soundfile,
                codec => 'WAV',
            });
        }
    
        $c->flash(messages => [{type => 'success', text => 'Sound File successfully changed!'}]);
        $c->response->redirect($c->stash->{handles_base_uri});
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub handles_delete :Chained('handles_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{file_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Sound File successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->stash->{handles_base_uri});
}

sub handles_download :Chained('handles_base') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;
    
    my %codec_mapping = (WAV => 'audio/x-wav');
    
    my $file_result = $c->stash->{file_result};
    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $file_result->filename . '"');
    $c->response->content_type(
        $codec_mapping{$file_result->codec} // 'application/octet-stream'); #'
    $c->response->body($file_result->data);
}

sub _transcode_sound_file {
    my ($self, $tmpfile, $source_codec, $target_codec) = @_;

    my $out;
    my @conv_args;
    
    ## quite snappy, but breaks SOAP (sigpipe's) and the catalyst devel server
    ## need instead to redirect like below

    given ($target_codec) {
        when ('PCMA') {
            @conv_args = ($tmpfile, qw/--type raw --bits 8 --channels 1 -A - rate 8k/);
        }
        when ('WAV') {
            if ($source_codec eq 'PCMA') {
                # this can actually only come from inside
                # certain files will be stored as PCMA (for handles with name "music_on_hold")
                @conv_args = ( qw/-A --rate 8k --channels 1 --type raw/, $tmpfile, "--type", "wav", "-");
            }
            else {
                @conv_args = ($tmpfile, qw/--type wav --bits 16 - rate 8k/);
            }
        }
    }
    
    $out = capturex([0], "/usr/bin/sox", @conv_args);
    
    return $out;
}

sub _clear_audio_cache {
    my ($self, $sound_set_id, $handle_name) = @_;

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    my @ret = $dispatcher->dispatch("appserver", 1, 1, <<EOF );
<?xml version="1.0"?>
  <methodCall>
    <methodName>postDSMEvent</methodName>
    <params>
      <param>
        <value><string>sw_audio</string></value>
      </param>
      <param>
        <value><array><data>
          <value><array><data>
            <value><string>cmd</string></value>
            <value><string>clearFile</string></value>
          </data></array></value>
          <value><array><data>
          <value><string>audio_id</string></value>
            <value><string>$handle_name</string></value>
         </data></array></value>
         <value><array><data>
           <value><string>sound_set_id</string></value>
           <value><string>$sound_set_id</string></value>
         </data></array></value>
       </data></array></value>
     </param>
   </params>
  </methodCall>
EOF

    if(grep { $$_[1] != 1 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        die "failed to clear SEMS audio cache";
    }

    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::Sound - Manage Sounds

=head1 DESCRIPTION

Show/Edit/Create/Delete Sound Sets.

Show/Upload Sound Files in Sound Sets.

=head1 METHODS

=head2 auto

Grants access to admin and reseller role.

=head2 sets_list

Basis for provisioning.voip_sound_sets.
Provides sets_rs in stash.

=head2 root

Display Sound Sets through F<sound/list.tt> template.

=head2 ajax

Get provisioning.voip_sound_sets from db and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a provisioning.voip_sound_sets row from the database by its id.
The resultset is exported to stash as "set_result".

=head2 edit

Show a modal to edit the Sound Set determined by L</base> using the form
L<NGCP::Panel::Form::SoundSet>.

=head2 delete

Delete the Sound Set determined by L</base>.

=head2 create

Show modal to create a new Sound Set using the form
L<NGCP::Panel::Form::SoundSet>.

=head2 handles_list

Basis for provisioning.voip_sound_handles grouped by voip_sound_groups with
the actual data in voip_sound_files.
Stashes:
    * handles_base_uri: To show L</pattern_root>
    * files_rs: Resultset of voip_sound_files in the current voip_sound_group
    * sound_groups: Hashref of sound_goups with handles JOIN files inside
        (used in the template F<sound/handles_list.tt>)

=head2 handles_root

Display Sound Files through F<sound/handles_list.tt> template accordion
grouped by sound_groups.

=head2 handles_base

Fetch a provisioning.voip_sound_files row from the database by the id
of the according voip_sound_handle. Create a new one if it doesn't exist but
do not immediately update the db.
The ResultClass is exported to stash as "file_result".

=head2 handles_edit

Show a modal to upload a file or set/unset loopplay using the form
L<NGCP::Panel::Form::SoundFile>.

=head2 handles_delete

Delete the Sound File determined by L</base>.

=head2 _transcode_sound_file

Transcodes the given sound file specified by a (temporary) filename.
This is ported from ossbss/lib/Sipwise/Provisioning/Voip.pm

For $target_codec 'PCMA' returns is RAW 8bit, 8kHz PCMA.
For $target_codec 'WAV' returns is WAV 16bit, 8kHz.

Will die if transcoding doesn't work.

=head2 _clear_audio_cache

Ported from ossbss.

tells our application server to clear a specific audio file

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
