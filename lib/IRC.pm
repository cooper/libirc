#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2012, the NoTrollPlzNet developers |
# Copyright (c) 2012, Mitchell Cooper              |
#---------------------------------------------------
package IRC;

use warnings;
use strict;
use utf8;
use 5.010;
use parent qw(EventedObject IRC::Functions::IRC);

use EventedObject;

use Scalar::Util 'weaken';

use IRC::User;
use IRC::Channel;
use IRC::Handlers;
use IRC::Utils;
use IRC::Functions::IRC;
use IRC::Functions::User;
use IRC::Functions::Channel;

our $VERSION = '1.1';

# create a new IRC instance
sub new {
    my ($class, %opts) = @_;
    
    bless my $irc = {}, $class;
    configure($irc, %opts);
    
    return $irc;
}

# configure the IRC object.
sub configure {
    my ($irc, %opts) = @_;
    state $c = 0;
    
    # apply default handlers.
    if (!$irc->{_applied_handlers}) {
        $irc->IRC::Handlers::apply_handlers();
        $irc->{_applied_handlers} = 1;
        
        $irc->{id} = $c++;
    }

    # create own user object.
    $irc->{me} ||= IRC::User->new($irc, $opts{nick});

    # Do we need SASL?
    if ($opts{sasl_user} && defined $opts{sasl_pass} && !$INC{'MIME/Base64.pm'}) {
        require MIME::Base64;
    }
    
}

# parse a raw piece of IRC data
sub parse_data {
    my ($irc, $data) = @_;

    $data =~ s/\0|\r//g; # remove unwanted characters

    # parse one line at a time
    if ($data =~ m/\n/) {
        $irc->parse_data($_) foreach split "\n", $data;
        return
    }

    my @args = split /\s/, $data;
    return unless defined $args[0];

    if ($args[0] eq 'PING') {
        $irc->send("PONG $args[1]");
    }

    # if there is no parameter, there's nothing to parse.
    return unless defined $args[1];

    my $command = lc $args[1];

    # fire the raw_* event (several of which fire more events from there on)
    $irc->fire_event("raw_$command", $data, @args);
    $irc->fire_event(raw => $data, @args); # for anything

}

# send login information.
sub login {
    my $irc = shift;
    
    my ($nick, $ident, $real, $pass) = (
        $irc->{nick}, 
        $irc->{user},
        $irc->{real},
        $irc->{pass}
    );
    
    # request capabilities.
    $irc->send('CAP LS');
    
    # send login information.
    $irc->send("PASS $pass") if defined $pass && length $pass;
    $irc->send("NICK $nick");
    $irc->send("USER $ident * * :$real");
    
    # SASL authentication.
    if ($irc->{sasl_user} && defined $irc->{sasl_pass}) {
        $irc->send('CAP REQ sasl');
        $irc->on(cap_ack_sasl => sub {
            $irc->send('AUTHENTICATE PLAIN');
            
            my $str = MIME::Base64::encode_base64(join("\0",
                $irc->{sasl_user},
                $irc->{sasl_user},
                $irc->{sasl_pass}
            ), '');
            
            if (!length $str) {
                $irc->send('AUTHENTICATE +');
                return;
            }
            
            else {
                while (length $str >= 400) {
                    my $substr = substr $str, 0, 400, '';
                    $irc->send("AUTHENTICATE $substr");
                }
                
                if (length $str) {
                    $irc->send("AUTHENTICATE $str");
                }
                
                else {
                    $irc->send("AUTHENTICATE +");
                }
            }
        });
    }
    
    # SASL not enabled.
    else { $irc->send('CAP END') }
    
}

# send data.
sub send {
    my ($irc, $data) = @_;
    $irc->fire_event(send => $data);
}

# return a channel from its name
sub channel_from_name {
    my ($irc, $name) = @_;
    IRC::Channel::from_name($irc, $name);
}

# create a new channel by its name
# or return the channel if it exists
sub new_channel_from_name {
    my ($irc, $name) = @_;
    IRC::Channel->new_from_name($irc, $name);
}

# create a new user by his nick
# or return the user if it exists
sub new_user_from_nick {
    my ($irc, $nick) = @_;
    IRC::User->new_from_nick($irc, $nick);
}

# return a user by his nick
sub user_from_nick {
    my ($irc, $nick) = @_;
    IRC::User::from_nick($irc, $nick);
}

# create a new user by his :nick!ident@host string
# or return the user if it exists
sub new_user_from_string {
    my ($irc, $nick) = @_;
    IRC::User->new_from_string($irc, $nick);
}

# return a user by his :nick!ident@host string
sub user_from_string {
    my ($irc, $nick) = @_;
    IRC::User::from_string($irc, $nick);
}

# determine if the ircd we're connected to suppots a particular capability.
sub has_cap {
    my ($irc, $cap) = @_;
    return $irc->{ircd}->{capab}->{lc $cap};
}

# determine if we have told the server we want a CAP, and the server is okay with it.
sub cap_enabled {
    my ($irc, $cap) = @_;
    return $irc->{active_capab}->{lc $cap};
}

sub _next_user_id {
    state $c = 'a';
    return shift->{id}.$c++;
}

sub id { shift->{id} }

# make a user permanent.
sub make_permanent {
    my ($irc, $user) = @_;
    delete $irc->{users}{$user};
    $irc->{users}{$user} = $user;
    $user->{permanent} = 1;
    return 1;
}

# make a user semi-permanent.
sub make_semi_permanent {
    my ($irc, $user) = @_;
    return if $user == $irc->{me}; # I am always permanent.
    weaken($irc->{users}{$user});
    delete $user->{permanent};
    return 1;
}

1
