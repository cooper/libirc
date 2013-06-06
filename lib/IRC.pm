#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2012, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
#---------------------------------------------------
package IRC;

# TODO LIST:
#
#   [x] use a consistent structure for storing ircd-related information in an IRC object
#   [x] make methods to fetch server capability information from RPL_ISUPPORT
#   [ ] make preset channel status levels for voice and halfop
#   [ ] create a class for manging multiple IRC servers
#   [x] make users and channels independent of IRC objects with ->add_*, ->remove_*, etc.
#   [ ] create a proper MODE handler
#   [ ] add feature to argument parser for type parameters such as source(u)
#   [x] move IRC parser to its own package
#

use warnings;
use strict;
use utf8;
use 5.010;
use parent qw(EventedObject IRC::Parser IRC::Functions::IRC);
use overload
    '""'     => sub { shift->{id} },            # string context  = ID
    '0+'     => sub { shift },                  # numeric context = memory address 
    'bool'   => sub { 1 },                      # boolean context = true
    '${}'    => sub { \shift->{network} },      # scalar deref    = network name
    '~~'     => \&_match,                       # smart matching
    fallback => 1;


use EventedObject;

use Scalar::Util qw(blessed);

use IRC::Pool;
use IRC::Server;
use IRC::Channel;
use IRC::User;
use IRC::Parser;
use IRC::Handlers;
use IRC::Utils;
use IRC::Functions::IRC;
use IRC::Functions::Server;
use IRC::Functions::Channel;
use IRC::Functions::User;

our $VERSION = '5.4';

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
        
        $irc->{id} = $c++.q(i);
    }

    # create pool, server, and own user object.
    if (!$irc->{server}) {
        $irc->{server}  = IRC::Server->new();
        $irc->{pool}    = IRC::Pool->new(irc  => $irc);
        $irc->{me}      = IRC::User->new(nick => $opts{nick});
        $irc->pool->add_user($irc->{me});
        $irc->pool->add_server($irc->{server});
        $irc->pool->retain($irc->{me}, 'me:is_me');
        $irc->pool->retain($irc->{server}, 'me:on_server');
        $irc->{server}->add_user($irc->{me});
    }

    # Do we need SASL?
    if ($opts{sasl_user} && defined $opts{sasl_pass} && !$INC{'MIME/Base64.pm'}) {
        require MIME::Base64;
    }
    
}

#############################
### SENDING OUTGOING DATA ###
#############################

# send data.
sub send {
    my ($irc, $data) = @_;
    $irc->fire_event(send => $data);
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
    
    $irc->{supported_cap} = [qw(sasl extended-join multi-prefix account-notify away-notify)];
    $irc->send_cap_request($_) foreach qw(extended-join multi-prefix account-notify away-notify);
    
    # SASL authentication.
    if ($irc->{sasl_user} && defined $irc->{sasl_pass}) {
        $irc->send_cap_request('sasl', 1);
    }
    
}

#############################################
### FETCHING USERS, CHANNELS, AND SERVERS ###
#############################################

# return a channel from its name
sub channel_from_name {
    my ($irc, $name) = @_;
    return $irc->pool->get_channel($name);
}

# create a new channel by its name
# or return the channel if it exists
sub new_channel_from_name {
    my ($irc, $name) = @_;
    return $irc->pool->get_channel($name)
    || $irc->pool->add_channel( IRC::Channel->new(
        pool => $irc->pool,
        name => $name
    ) );
}

# create a new user by his nick
# or return the user if it exists
sub new_user_from_nick {
    my ($irc, $nick) = @_;
    return $irc->user_from_nick($nick)
    || $irc->pool->add_user( IRC::User->new(
        pool => $irc->pool,
        nick => $nick
    ) );
}

# return a user by his nick
sub user_from_nick {
    my ($irc, $nick) = @_;
    return $irc->pool->get_user($nick);
}

# create a new user by his :nick!ident@host string
# or return the user if it exists
sub new_user_from_string {
    my ($irc, $user_string) = @_;
    $user_string =~ m/^:*(.+)!(.+)\@(.+)/ or return;
    my ($nick, $ident, $host) = ($1, $2, $3);
    return $irc->user_from_string($user_string)
    || $irc->pool->add_user( IRC::User->new(nick => $nick) );
        
    # TODO: host/ident change.
    
}

# return a user by his :nick!ident@host string
sub user_from_string {
    my ($irc, $user_string) = @_;
    $user_string =~ m/^:*(.+)!(.+)\@(.+)/ or return;
    my ($nick, $ident, $host) = ($1, $2, $3);

    # find the user.
    my $user = $irc->pool->get_user($nick);
    
    # TODO: host/ident change.

    return $user;
}

# return a server from its name
sub server_from_name {
    my ($irc, $name) = @_;
    $name =~ s/^://;
    return $irc->pool->get_server($name);
}

# create a new server by its name
# or return the server if it exists
sub new_server_from_name {
    my ($irc, $name) = @_;
    $name =~ s/^://;
    return $irc->pool->get_server($name)
    || $irc->pool->add_server( IRC::Server->new(
        pool => $irc->pool,
        name => $name
    ) );
}

##########################
### IRCv3 CAPABILITIES ###
##########################

# request a CAP.
# if the capability requires additional registration commands
# (SASL, for example, requires authentication to complete),
# it should pass 1 as the third argument and call $irc->continue_login()
# when that registration extension is complete.
sub send_cap_request {
    my ($irc, $cap, $wait) = @_;
    if ($wait) {
        $irc->wait_login;
        $irc->{waiting_cap}{lc $cap} = 1;
    }
    $irc->{pending_cap} ||= [];
    push @{ $irc->{pending_cap} }, lc $cap;
}

# add a wait during login.
sub wait_login {
    my $irc = shift;
    $irc->{login_refcount} ||= 0;
    $irc->{login_refcount}++;
    return $irc->{login_refcount};
}

# release a wait during login.
sub continue_login {
    my $irc = shift;
    $irc->{login_refcount} ||= 0;
    $irc->{login_refcount}--;
    $irc->_check_login;
    return $irc->{login_refcount};
}

# internal: check if CAP negotiation is complete.
sub _check_login {
    my $irc = shift;
    return if $irc->{login_refcount} && $irc->{login_refcount} >= 0;
    $irc->send('CAP END');
    delete $irc->{login_refcount};
}

# send pending CAP requests.
sub _send_cap_requests {
    my $irc = shift;
    return unless $irc->{pending_cap};
    $irc->send('CAP REQ :'.join(' ',
        grep { $irc->server->has_cap($_) } @{ $irc->{pending_cap} }
    ));
}

#########################
### INTERNAL ROUTINES ###
#########################

# smart matching
sub _match {
    my ($irc, $other) = @_;
    
    # anything that is not blessed is a no no.
    return unless blessed $other;
    
    # anything else, check if it belongs to this IRC object.
    return ($other->can('irc') ? $other->irc : $other->{irc} or -1) == $irc;
    
}


# arg parser alias.
sub args;
*args = *IRC::Parser::args;

# fetchers.
sub id     { shift->{id}     }
sub pool   { shift->{pool}   }
sub server { shift->{server} }

1
