#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-12, Mitchell Cooper           |
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
    '~~'     => sub { $_[1]->has_user($_[0]) }, # smart match     = user in channel
    fallback => 1;

use Scalar::Util 'weaken';

#####################
### CLASS METHODS ###
#####################

sub new {
    my ($class, %opts) = @_;

    # create a new user object   
    bless my $user = {
        events   => {},
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
    my ($user, $newnick) = @_;
    my $irc = $user->irc;

    delete $irc->{nicks}{ lc $user->{nick} };

    my $oldnick                = $user->{nick};
    $user->{nick}              = $newnick;
    $irc->{nicks}{lc $newnick} = $user->id;

    # fire events
    $user->fire_event(nick_change => $oldnick, $newnick);
    
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

# set account name
sub set_account {
    my ($user, $account) = @_;
    $user->{account} = $account;
}

sub id   { shift->{id}      }
sub irc  { shift->pool->irc }
sub pool { shift->{pool}    }

sub DESTROY {
    my $user = shift;

    # if the user belongs to a pool, remove it.
    $user->pool->remove_user($user) if $user->pool;
    
}

1
