#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
# User.pm: the user object class.                  |
#---------------------------------------------------
package IRC::User;

use warnings;
use strict;
use parent qw(EventedObject IRC::Functions::User);
use 5.010;

use overload
    '""'     => sub { shift->{id} },            # string context  = ID
    '0+'     => sub { shift },                  # numeric context = memory address 
    'bool'   => sub { 1 },                      # boolean context = true
    '${}'    => sub { \shift->{nick} },         # scalar deref    = nickname
    '~~'     => \&_match,                       # smart match
    fallback => 1;

use Scalar::Util 'blessed';

#####################
### CLASS METHODS ###
#####################

sub new {
    my ($class, %opts) = @_;

    # create a new user object   
    bless my $user = {
        channels => {},
        nick     => 'libirc', # default
        %opts
    }, $class;
    
    # assign a temporary identifier.
    $user->{id} = '[User '.($user + 0).q(]);

    return $user;
}

########################
### INSTANCE METHODS ###
########################

# change the nickname and move the object's location
sub set_nick {
    my ($user, $nick) = @_;
    my $old_nick  = $user->{nick};
    $user->{nick} = $nick;
    
    # change it in the pool.
    $user->pool->set_user_nick($user, $old_nick, $nick);

    # fire events
    EventedObject::fire_events_together(
        [ $user, nickname_changed => $old_nick, $nick ],
        [ $user, nick_change      => $old_nick, $nick ] # compatibility.
    );
    
}

# set hostname
sub set_host {
    my ($user, $host) = @_;
    my $old_host  = $user->{host};
    return if defined $host && defined $old_host && $old_host eq $host;
    $user->{host} = $host;
    $user->fire_event(hostname_changed => $old_host, $host);
}

# set username
sub set_user {
    my ($user, $username) = @_;
    my $old_user  = $user->{user};
    return if defined $username && defined $old_user && $old_user eq $username;
    $user->{user} = $username;
    $user->fire_event(username_changed => $old_user, $username);
}

# set realname
sub set_real {
    my ($user, $real) = @_;
    my $old_real  = $user->{real};
    return if defined $real && defined $old_real && $old_real eq $real;
    $user->{real} = $real;
    $user->fire_event(realname_changed => $old_real, $real);
}

# set account name
sub set_account {
    my ($user, $account) = @_;
    my $old_account  = $user->{account};
    return if defined $account && defined $old_account && $old_account eq $account;
    $user->{account} = $account;
    $user->fire_event(account_changed => $old_account, $account);
}

# set away reason.
# if we don't know the reason, use YES.
sub set_away {
    my ($user, $reason) = @_;
    my $old_away  = $user->{away};
    return if defined $reason && defined $old_away && $old_away eq $reason;
    $user->{away} = $reason;
    $user->fire_event(away_changed => $old_away, $reason);
    $user->fire('returned_from_away') if !defined $reason;
}

# returns a list of channels the user is on
sub channels {
    return values %{ shift->{channels} };
}

# in a common channel with..
sub in_common {
    my ($user, $other_user) = @_;
    foreach my $channel ($user->channels) {
        return 1 if $channel->has_user($other_user)
    }
    return;
}

sub id     { shift->{id}      }
sub irc    { shift->pool->irc }
sub pool   { shift->{pool}    }
sub server { $_[0]->pool->get_server($_[0]->{server}) }

# smart matching
sub _match {
    my ($user, $other) = @_;
    
    # anything that is not blessed is a no no.
    return unless blessed $other;
    
    # for channels, check if the user is in the channel.
    if ($other->isa('IRC::Channel')) {
        return $other->has_user($user);
    }
    
    # if it's another user, check if they share common channel(s).
    if ($other->isa('IRC::User')) {
        return $user->in_common($other);
    }
    
    # for IRC objects, check if the user belongs to that server.
    if ($other->isa('IRC')) {
        return $other == $user->{irc};
    }
    
    return;
}

sub DESTROY {
    my $user = shift;

    # if the user has a stored server, release the reference to it.
    if (defined $user->server) {
        $user->server->remove_user($user);
    }

    # if the user belongs to a pool, remove it.
    $user->pool->remove_user($user) if $user->pool;
    
}


1
