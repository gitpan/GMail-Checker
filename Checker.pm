package GMail::Checker;

# Perl interface to the gmail notifier
# Allows you to check new mails, retrieving the number of new mails, sender and subject

# $Id: Checker.pm,v 1.01 2004/11/29 02:47:11 sacred Exp $

use strict;
use IO::Socket::SSL;
use Carp;
use vars qw($VERSION);

$VERSION = 1.00;

sub version { sprintf("%f", $VERSION); }

sub new {
    my $self = {};
    my $proto = shift;
    my %params = @_;
    $self->{SOCK} = undef;
    $self->{NBMSG} = 0;
    my $class = ref($proto) || $proto;
    bless($self,$class);
    $self->login($params{"USERNAME"}, $params{"PASSWORD"}) if ((exists $params{"USERNAME"}) and (exists $params{"PASSWORD"}));
    return $self;
}

sub DESTROY {
    my $self = shift;
    if (defined $self->{SOCK}) { $self->{SOCK}->close(); }
}

sub getsize { # Formatting the mail[box] size in a pretty manner
    my $self = shift;
    my $size = shift;
    $size /= 1024;
    my $unit = "Kbytes";
    ($size, $unit) = ($size/1024, "Mbytes") if (($size / 1024) > 1) ;
    return ($size, $unit);
}

sub login {
    my $self = shift;
    my ($login, $passwd) = @_;
    my $not = new IO::Socket::SSL "pop.gmail.com:995" or die IO::Socket::SSL->errstr();
    $self->{SOCK} = $not;
    my $line = <$not>; # Reading the welcome message
    print $not "USER $login\r\n";
    $line = <$not>;
    if ($line !~ /^\+OK/) { print "Wrong username, please check your settings.\n"; $self->close(); } # We are not allowing USER on transaction state.
    print $not "PASS $passwd\r\n";
    $line = <$not>;
    if ($line !~ /^\+OK/) { print "Wrong password, please check your settings.\n"; $self->close(); } # Same as above for PASS.
}

sub get_msg_nb_size {
    my $self = shift;
    if (defined $self->{SOCK}) {
	my $gsocket = $self->{SOCK};
	print $gsocket "STAT\r\n";
	my $gans = <$gsocket>;
	unless ($gans !~ /^\+OK\s(\d+)\s(\d+)(\s.*)?\r\n/) {
	    return ($1,$2); # Sending the number of messages and the size of the mailbox 
	}
    } else { croak "Operation failed, connection to server is not established.\n"; }
}

sub get_pretty_nb_messages {
    my $self = shift;
    my %params = @_;
    $params{"ALERT"} = "TOTAL_MSG" unless exists $params{"ALERT"}; # Making sure we have an alert type.
    if (defined $self->{SOCK}) {
	my $gsocket = $self->{SOCK};
	print $gsocket "STAT\r\n";
	my $gans = <$gsocket>;
	unless ($gans !~ /^\+OK\s(\d+)\s(\d+)(\s.*)?\r\n/) {
	    if ($params{"ALERT"} eq "NEW_MSG_ONLY") {
		if ($1 > $self->{NBMSG}) {
		    return sprintf "You have %d new messages.\n", $1 - $self->{NBMSG};
		}
	    }
	    $self->{NBMSG} = $1;
	    return sprintf "You have $1 messages in your inbox (size %0.2f %s)\n", $self->getsize($2) unless $params{"ALERT"} eq "NEW_MSG_ONLY";
	}
    } else { croak "Operation failed, connection to server is not established.\n"; }
}

sub get_msg_size {
    my $self = shift;
    my %params = @_;
    if (defined $self->{SOCK}) {
	my (@msg_size, $gans);
	my $gsocket = $self->{SOCK};
	if (exists $params{"MSG"}) {
	    print $gsocket "LIST " . $params{"MSG"} . "\r\n";
	    $gans = <$gsocket>;
	    if ($gans =~ /^\+OK\s(\d+)\s(\d+)/) {
		($msg_size[0]->{nb}, $msg_size[0]->{size}) = ($1, $2);
		return @msg_size;
	    } else { print "No such message number.\r\n"; }
	} else {
	    print $gsocket "LIST\r\n";
	    my $i = 0;
	    for ($gans = <$gsocket>; $gans ne ".\r\n"; $gans = <$gsocket>) {
		if ($gans =~ /^(\d+)\s(\d+)/) {
		    ($msg_size[$i]->{nb}, $msg_size[$i]->{size}) = ($1, $2);
		    $i++;
		}
	    }
	    ($msg_size[0]->{nb}, $msg_size[0]->{size}) = (-1,-1) if $i == 0; # Mailbox is empty
	    return @msg_size;
	}
    }
}

sub get_msg {
    my $self = shift;
    my %params = @_;
    if (defined $self->{SOCK}) {
	my (@msgs, $gans);
	my $gsocket = $self->{SOCK};
	if (exists $params{"MSG"}) {
	    print $gsocket "RETR " . $params{"MSG"} . "\r\n";
	    my $msgl = "";
	    $gans = <$gsocket>;
	    if ($gans =~ /^\+OK\s/) {
		do {
		    $gans = <$gsocket>;
		    $msgl .= $gans  if $gans =~ /^([A-Z][a-zA-Z0-9-]+:\s+|\t)/;
		} while ($gans ne "\r\n");
		$msgs[0]->{headers} = $msgl;
		$msgl = "";
		do {
		    $gans = <$gsocket>;
		    $msgl .= $gans;
		} while ($gans ne ".\r\n");
		$msgs[0]->{body} = $msgl;
		print $gsocket "DELE " . $params{"MSG"} ."\r\n" if exists $params{"DELETE"};
		return @msgs;
	    } else { print "No such message number (" .  $params{"MSG"}  .").\r\n"; }
	} else {
	    my $total = shift(@{ $self->get_msg_nb_size() } );
	    for (my $ind = 1; $ind < $total; $ind++) {
		print $gsocket "RETR $ind\r\n";
		my ($i, $msgl) = (0, "");
		$gans = <$gsocket>;
		if ($gans =~ /^\+OK\s/) {
		    do {
			$gans = <$gsocket>;
			$msgl .= $gans  if $gans =~ /^([A-Z][a-zA-Z0-9-]+:\s+|\t)/;
		    } while ($gans ne "\r\n");
		    $msgs[$ind]->{headers} = $msgl;
		    $msgl = "";
		    for ($gans = <$gsocket>; $gans ne ".\r\n"; $gans = <$gsocket>) { $msgl .= $gans; }
		    $msgs[$ind]->{body} = $msgl;
		    print $gsocket "DELE $ind\r\n" if exists $params{"DELETE"};
		} else { print "No such message number (" .  $params{"MSG"}  .").\r\n"; }
	    }
	    return @msgs;
	}
    }
}

sub get_msg_headers {
    my $self = shift;
    my %params = @_;
    $params{"HEADERS"} = "MINIMAL" unless exists $params{"HEADERS"}; # Making sure we have headers type for retrieval.
    my $headregx = ($params{"HEADERS"} eq "FULL") ? '^([A-Z][a-zA-Z0-9-]+:\s+|\t)' : '^(From|Subject|Date):\s+'; # Headers regexp
    my @messages = [];
    if (defined $self->{SOCK}) {
	my $gsocket = $self->{SOCK};
	my ($lastmsg, $gans) = (undef, undef);
	if (!exists $params{"MSG"}) {  # By default we get the last message's headers.
	    print $gsocket "STAT\r\n";
	    $gans = <$gsocket>;
	    if ($gans =~ /^\+OK\s(\d+)\s\d+(\s.*)?\r\n/) {
		$lastmsg = $1;
	    } 
	} else { # Did we specify a message for which we want headers ? 
	    $lastmsg = $params{"MSG"};
	}
	print $gsocket "TOP $lastmsg 1\r\n";
	$gans = <$gsocket>;
	if ($gans =~ /^\+OK/) {
	    do {
		$gans = <$gsocket>;
		push(@messages, $gans)  if $gans =~ /$headregx/;
	    } while ($gans ne "\r\n");

	} else { print "No such message number.\r\n"; } # Duh! We received an -ERR
	return @messages;
    } else { croak "Operation failed, socket is not open.\n"; }
}

sub get_uidl {
      my $self = shift;
      my %params = @_;
   if (defined $self->{SOCK}) {
	my (@uidls, $gans);
	my $gsocket = $self->{SOCK};
	if (exists $params{"MSG"}) {
	    print $gsocket "UIDL " . $params{"MSG"} . "\r\n";
	    $gans = <$gsocket>;
	    if ($gans =~ /^\+OK\s\d+\s<([\x21-\x7E]+)>\r\n/) { return $1; } else {  print "No such message number (" .  $params{"MSG"}  .").\r\n"; return -1;}
	} else { 
	    print $gsocket "UIDL\r\n";
	    my $i = 0;
	    for ($gans = <$gsocket>; $gans ne ".\r\n"; $gans = <$gsocket>) {
		if ($gans =~ /^(\d+)\s<([\x21-\x7E]+)>\r\n/) {
		    ($uidls[$i]->{nb}, $uidls[$i]->{hash}) = ($1, $2);
		    $i++;
		}
	    }
	    ($uidls[0]->{nb}, $uidls[0]->{hash}) = (-1,-1) if $i == 0;
	    return @uidls;
	}
    } else { croak "Operation failed, socket is not open.\n"; }
}

sub rset {
    my $self = shift;
    if (defined $self->{SOCK}) {
	my $gsocket = $self->{SOCK};
	print $gsocket "RSET\r\n";
	my $gans = <$gsocket>;
	return $gans;
    } else { croak "Operation failed, socket is not open.\n"; }
}

sub close {
    my $self = shift;
    if (defined $self->{SOCK}) { 
	my $gsocket = $self->{SOCK};	    
	print $gsocket "QUIT\r\n"; # Sending a proper quit to the server so it can make an UPDATE in case DELE requests were sent.
	$gsocket->close(SSL_ctx_free => 1); # Freeing the connection context
	$self->{SOCK} = undef;
    } else { croak "Operation failed, socket is not open.\n"; }
}


__END__

=head1 NAME

GMail::Checker - Wrapper for Gmail accounts

version 1.00

=head1 SYNOPSIS

    use GMail::Checker;

    my $gwrapper = new GMail::Checker();
    my $gwrapper = new GMail::Checker(USERNAME => "username, PASSWORD => "password");

    # Let's log into our account (using SSL)
    $gwrapper->login("username","password");

    # Get the number of messages in the maildrop & their total size
    my ($nb, $size) = $gwrapper->get_msg_nb_size();

    # Do we have new messages ?
    my $alert =  $gwrapper->get_pretty_nb_messages(ALERT => "TOTAL_MSG");

    # Get the headers for a specific message (defaults to last message)
    my @headers = $gwrapper->get_msg_headers(HEADERS => "FULL", MSG => 74);

    # Get a message size
    my ($msgnb, $msgsize) = $gwrapper->get_msg_size(MSG => 42);

    # Retrieve a specific message
    my @msg = $gwrapper->get_msg(MSG => 23);

    # Retrieve UIDL for a message
    my @uidl = $gwrapper->get_uidl(MSG => 10);
    
=head1 DESCRIPTION

This module provides a wrapper that allows you to perform major operations on your gmail account.

You may create a notifier to know about new incoming messages, get information about a specific e-mail,

retrieve your mails using the POP3 via SSL interface.

=head1 METHODS

The implemented methods are :

=over 4

=item new


Creates the wrapper object.

The L<IO::Socket::SSL> object is stored as $object->{SOCK}.

It currently only accepts username and password as hash options.

=over 4

=item C<USERNAME>

Your GMail account username (without @gmail.com).

=item C<PASSWORD>

Your GMail password.

=back 4

=item C<get_msg_nb_size>


This method checks your maildrop for the number of messages it actually contains and their total size.

It returns an array which consists of (message_numbers, total_size).

Example :

    my ($msgnb, $size) = $gwrapper->get_msg_nb_size();
    or my @maildrop = $gwrapper->get_msg_nb_size();

=item C<get_pretty_nb_messages>


Alerts you when you have new mails in your mailbox.

It takes as a hash argument ALERT which can have two values :

=over 4

=item C<NEW_MSG_ONLY> 

Gives you only the number of new messages that have arrived in your mailbox since the last check.

=item C<TOTAL_MSG> 

Gives you the total number of messages and the actual size of the mailbox prettily formatted.

=back 4

=item C<get_msg_size>


This methods retrieves the messages size.

By default, it will return an array containing all the messages with message number and its size.

Given the hash argument MSG, size information will be returned for that message only.

Returns (-1,-1) if the mailbox is empty.

Example :

    my @msg_sizes = $gwrapper->get_msg_size();
    foreach $a (@msg_sizes) { print "Message number %d - size : %d", $a->{nb>, $a->{size}; }
    my @specific_msg_size = $gwrapper->get_msg_size(MSG => 2);
    printf "Message number %d - size : %d", $specific_msg_size[0]->{nb>, $specific_msg_size[0]->{size};

=item C<get_msg>


Retrieves a message from your mailbox and returns it as an array.

If no message number is specified, it will retrieve all the mails in the mailbox.

Returns an empty array if there is no message matching the request or mailbox is empty.

The method accepts as hash arguments :

=over 4

=item C<MSG> 

The message number

=item C<DELETE> 

Deletes the message from the server

=back 4

By default the messages are kept in the mailbox.

Do not forget to specify what happens to the mails that have been popped in your Gmail account settings.

Example :

    my @msg = $gwrapper->get_msg(MSG => 2, DELETE => 1);
    print $msg[0]->{headers}, $msg[0]->{body};

In case all messages are returned, just loop over the array to get them.

=item C<get_msg_headers>


Retrieves a message header and returns them as an array (one header item per line).

If no message number is specified, the last message headers will be retrieved.

The function takes two type of arguments as hashes

=over 4

=item C<MSG> 

The message number

=item C<HEADERS>

Takes two values, I<FULL> for full headers and I<MINIMAL> for From, Subject and Date only.

=back 4

Returns an I<empty array> if there is no message matching the request or mailbox is empty.

Example :

    my @headers = $gwrapper->get_msg_headers(HEADERS => "FULL", MSG => 3);
    foreach $h (@headers) { print $h; }

=item C<get_uidl>


Gets messages UIDL (unique-Id [hash] attributed to the message by the server).

Takes as a hash argument the MSG number or retrieves the UIDLs for all the messages.

I<Returns (-1,-1) if the mailbox is empty>.

Example :

    my @uidls = $gwrapper->get_uidl();
    foreach $uid (@uidls) { print $uid->{nb}, " ", $uid->{hash}; }
    my $spec_uid = $gwrapper->get_uidl(MSG => 1);

=item C<rset>


If any messages have been marked as deleted by the POP3 server, they are unmarked.

=item C<close>


Closes the connection after sending a QUIT command so the server properly switches to the UPDATE state.

It doesn't take any argument for now.

=back 4

=head1 VERSION

1.00

=head1 COPYRIGHT

Copyright 2004 by Faycal Chraibi. All rights reserved.

This library is a free software. You can redistribute it and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Faycal Chraibi <fays@cpan.org>

=head1 TODO

- Include charsets conversions support

- Search through mails and headers

- Include mail storing/reading option

- Headers regexp argument for headers retrieval

- Correct bugs ?

=head1 SEE ALSO

L<IO::Socket::SSL>, L<WWW::GMail>

