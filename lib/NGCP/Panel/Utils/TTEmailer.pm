package NGCP::Panel::Utils::TTEmailer;

sub send_email{
  my $self = shift;
  my ($email,$hr_tmpl,$hr_vars) = @_;
  my ($email,$subject,$text,$from,$type,$headers,$images,$binatt) = @$hr_mail{qw/email subject text from type headers images binatt/};
  my $cfg = Knetrix::Config->get;

  # If we don't specify the email body then fetch it from t_$view_${action}email.tt2
  if(!$text){
    $text = '';
    $hr_tmpl->{$_} ||= ${$self->{OUT_DATA}{request}}{$_} foreach qw/module sub_module view action/;
    if(!$hr_tmpl->{tmplnamestrict}){
      $hr_tmpl->{action} .= 'email';
    }
    $hr_tmpl->{error} = 0;

    my $stc = {};
    my $tt2 = Knetrix::Template->instance() || throw Knetrix::Error -text=>"Missing tt2 obj";

    if(ref $hr_vars eq 'HASH'){
      use Hash::Merge ();
      $hr_vars = Hash::Merge::merge $self->{OUT_DATA} , $hr_vars;
    } else {
      $hr_vars = $self->{OUT_DATA};
    }
    (@{$hr_vars->{config}}{qw/http httpdata data/},@{$hr_vars->{tmpl_hash}}{qw/module sub_module/}) 
      = ($cfg->dir_config('http'),$cfg->dir_config('httpdata'),$cfg->dir_config('systemdata'),@$hr_tmpl{qw/module sub_module/});
    $hr_vars->{tmpl_req} = $hr_tmpl;
    # Some funky magic to access variables inside the template
    $hr_vars->{import} ||= $stc;
    my $importold = $Template::Stash::HASH_OPS->{ import } if defined $Template::Stash::HASH_OPS->{ import };
    $Template::Stash::HASH_OPS->{ import } = sub { $stc = $_[0] };
    $log->error(Dumper $hr_tmpl);
    $log->error(Dumper $self->{OUT_DATA}{request});
    $hr_tmpl = Knetrix::Template::Magic->wand($hr_tmpl);
    my $ok = $tt2->process($hr_tmpl,$hr_vars,\$text) || $log->error($tt2->error());
    $Template::Stash::HASH_OPS->{ import } = $importold if defined $importold;
    $subject ||= $stc->get('subject');
    $type    ||= $stc->get('mimetype');
    $from    ||= $stc->get('from');
  }

  # If from isn't specified fetch it from knetrix.xml or use support@envisionext.com
  if(!$from){
    $from = $cfg->dir_config('from','email') || 'support@envisionext.com';
  }

  # Extract the Images from the template/mail body
  $images ||= {};
  sub collect_images{
    my ($q1,$image,$q2,$images) = @_;
    $log->error(Dumper \@_);
    my($path,$filename) = $image =~/(.*?)([^\/]+\/?)$/;
    $log->error("path is $path filename is $filename");
    $images->{$filename} = $path;
    return $q1.$filename.$q2;
  }
  $text =~s/(['"]cid:)([^'"]+)(['"])/collect_images($1,$2,$3,$images)/ge;

  my $imagescnt = scalar keys(%$images);
  if($binatt){
    ref $binatt eq 'HASH' and $binatt = [$binatt];
    ref $binatt eq 'ARRAY' and $imagescnt += scalar @$binatt;
  }
  $log->debug("imagescnt=",$imagescnt,"; text=",$text,"images=",Dumper $images);

  # Set the mail type based on the existence of any images
  my %msgadd;
  if ($imagescnt) {
    %msgadd = ( Type => 'multipart/related' );
  } else {
    %msgadd = ( Type    => $type?$type:'text/html',
		Data    => $text,
	      );
  }
  # Setup the mail object
  my $msg = MIME::Lite->new( To      => $email,
			     From    => $from,
			     Subject => $subject,
			     %msgadd,
			   );
  # Setup a debug email for the postmaster
  my $debugmsg = MIME::Lite->new( To      => $cfg->dir_config('postmaster','email') || 'ric@envisionext.com',
				  From    => $from,
				  Subject => $subject,
				  %msgadd,
				);
  # Attach the body and any images
  if($imagescnt){
    $msg->attach( Data    => $text,
		  Type    => 'text/html',
		);
    $debugmsg->attach( Data    => $text."<pre>Util::send_email\n\n\nTo:$email;".(Dumper([$hr_mail,$hr_vars]))."\n</pre>",
		       Type    => 'text/html',
		     );
    # Attach the images
    my $datadir = $cfg->dir_config('staticdata');
    while( my ($img,$path) = each(%$images) ){
      my ($ext) = $img=~/[^\.]+\.(.+)$/;
      $msg->attach( Type => $mimetypes{$ext},
		    Id   => $img,
		    Path => join '/', $datadir,$path,$img,
		  );
      $debugmsg->attach( Type => $mimetypes{$ext},
			 Id   => $img,
			 Path => join '/', $datadir,$path,$img,
		       );
    }
    foreach (_afy $binatt){
      $msg->attach( %$_);
      $debugmsg->attach( %$_);
    }
  }
  my $res;
  print STDERR Dumper $msg;
  if(!$hr_mail->{dontsend}){
    my @params = split(':',$cfg->dir_config('server','email'));
    $res = $msg->send(@params) unless $cfg->dir_config('safemode','email');;
    $debugmsg->send(@params) if $cfg->dir_config('debug','email');
  }else{
    $res = 1;
  }
  return ($res,$msg,$debugmsg)
}


1;
