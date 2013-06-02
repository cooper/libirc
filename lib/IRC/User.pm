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
    my ($class, $irc, $nick) = @_;
    $nick ||= 'libirc';

    # create a new user object
    my $id = $irc->_next_user_id;
    
    $irc->{users}{$id} = bless my $user = {
        nick     => $nick,
        events   => {},
        id       => $id,
        channels => {}
    }, $class;
    weaken($irc->{users}{$id});
    $irc->{nicks}{lc $nick} = $id;

    # reference weakly to the IRC object.
    $user->{irc} = $irc;
    weaken($user->{irc});
    
    # make the IRC object a listener.
    $user->add_listener($irc, 'user');

    # fire new user event
    $user->fire_event(new => $user);

    return $user;
}

# parses a :nick!ident@host
# and finds the user
sub from_string {
    my ($irc, $user_string) = @_;
    $user_string =~ m/^:*(.+)!(.+)\@(.+)/ or return;
    my ($nick, $ident, $host) = ($1, $2, $3);

    # find the user.
    my $user = from_nick($irc, $nick);
    
    # TODO: host change events.

    return $user;
}

# parses a :nick!ident@host
# and creates a new user if it doesn't exist
# finds it if it does
sub new_from_string {
    my ($package, $irc, $user_string) = @_;
    $user_string =~ m/^:*(.+)!(.+)\@(.+)/ or return;
    my ($nick, $ident, $host) = ($1, $2, $3);
    return from_string($irc, $user_string) || do {
        my $user = $package->new($irc, $nick);
        # set host
        # set ident
        $user
    };
}

# find a user by his nick
sub from_nick {
    my ($irc, $nick) = @_;

    # find the user.
    my $user;
    my $id = $irc->{nicks}{lc $nick};
    if (defined $id) {
        $user = $irc->{users}{$id};
        delete $irc->{nicks}{lc $nick} unless $user;
    }
    
    return $user;
}

# find a user by his nick
# or create one if it doesn't exist
sub new_from_nick {
    my ($package, $irc, $nick) = @_;
    return from_nick($irc, $nick) || $package->new($irc, $nick);
}

########################
### INSTANCE METHODS ###
########################

# change the nickname and move the object's location
sub set_nick {
    my ($user, $newnick) = @_;
    my $irc = $user->{irc};

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
    return
}

# set account name
sub set_account {
    my ($user, $account) = @_;
    $user->{account} = $account;
}

sub id { shift->{id} }

1
