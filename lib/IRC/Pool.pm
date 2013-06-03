#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# Copyright (c) 2012-13, Mitchell Cooper           |
#---------------------------------------------------
package IRC::Pool;

use warnings;
use strict;
use utf8;
use 5.010;

use Scalar::Util 'weaken';

# create a new pool.
sub new {
    my ($class, %opts) = @_;
    my $pool = bless \%opts, $class;
    weaken($pool->{irc});
    return $pool;
}

sub irc { shift->{irc} }

######################
### MANAGING USERS ###
######################

# if the passed value starts with a number, it is assumed to be
# a user ID, and the method will return a user with that ID.
# if it does not start with a number, it is assumed to be the
# user's nickname, and a user with that nickname will be returned.
sub get_user {
    my ($pool, $id_or_nick) = @_;
    return $pool->{users}{$id_or_nick}               ||
    exists $pool->{nicks}{lc $id_or_nick}            ?
    $pool->{users}{ $pool->{nicks}{lc $id_or_nick} } :
    undef;
}

# add a user to the pool.
sub add_user {
    my ($pool, $user) = @_;
    return $user if exists $user->{id} && $pool->{users}{$user};
    
    # use the next available ID.
    my $id = $user->{id} = $pool->_next_user_id;
    
    # weakly reference to the user.
    # this will be strengthened when the user is retained.
    $pool->{users}{$id}     = $user;
    $pool->{ref_count}{$id} = 0;
    weaken($pool->{users}{$id});
    
    # reference to the pool.
    $user->{pool} = $pool;
    
    # weakly reference to the IRC object.
    # this is very silly, but it still here for compatibility.
    $user->{irc} = $pool->irc;
    weaken($user->{irc});
    
    # store the nickname.
    $pool->{nicks}{ lc $user->{nick} } = $id;
    
    # make the IRC object a listener.
    $user->add_listener($pool->irc, 'user');
    
    return $user;
}

# remove a user from the pool.
sub remove_user {
    my ($pool, $user) = @_;
    return unless $pool->{users}{$user};
    
    delete $pool->{nicks}{ lc $user->{nick} };
    delete $pool->{users}{$user};
    
    # remove the user from channels.
    # this is actually done in other places and is just a harmless
    # double-check to prevent reference chains.
    if ($user->channels) {
        $_->remove_user($user) foreach $user->channels;
    }
    
    return 1;
}

# increase reference count.
sub retain {
    my ($pool, $obj) = @_;
    my $refcount = ++$pool->{ref_count}{$obj};
    
    return $refcount if $refcount != 1;
    
    # refcount has been incremented to one.
    # store the user semi-permanently.

    my $type = 'objects';
    $type = 'users'    if $obj->isa('IRC::User');
    $type = 'channels' if $obj->isa('IRC::Channel');

    # re-reference.
    delete $pool->{$type}{$obj};
    $pool->{$type}{$obj} = $obj;
    
    return 1;
}

# decrease reference count.
sub release {
    my ($pool, $obj) = @_;
    my $refcount = --$pool->{ref_count}{$obj};
    
    return $refcount if $refcount;

    # users.
    $pool->remove_user($obj) if $obj->isa('IRC::User');
    
    # channels.
    if ($obj->isa('IRC::Channel')) {
        $obj->remove_user($_) foreach $obj->users;
        $pool->remove_channel($obj);
    }

    return 0;
}

# fetch next available user ID.
sub _next_user_id {
    my $pool = shift;
    $pool->{_cid} ||= 'a';
    return $pool->irc->id.$pool->{_cid}++;
}

#########################
### MANAGING CHANNELS ###
#########################

# fetch a channel from its ID or name.
sub get_channel {
    my ($pool, $name) = @_;
    return $pool->{channels}{$name} || $pool->{channels}{ $pool->irc->id.lc($name) }
}

# add channel to the pool.
sub add_channel {
    my ($pool, $channel) = @_;
    return $channel if exists $channel->{id} && $pool->{channels}{$channel};

    my $id = $channel->{id} = $pool->irc->id.lc($channel->{name});

    # weakly reference to the channel.
    # this will be strengthened when the channel is retained.
    $pool->{channels}{$id} = $channel;
    weaken($pool->{channels}{$id});
    
    # reference to the pool.
    $channel->{pool} = $pool;
    
    # weakly reference to the IRC object.
    # this is very silly, but it still here for compatibility.
    $channel->{irc} = $pool->irc;
    weaken($channel->{irc});
    
    # make the IRC object a listener.
    $channel->add_listener($pool->irc, 'channel');

    return $channel;
}

# remove a channel from the pool.
sub remove_channel {
    my ($pool, $channel) = @_;
    delete $pool->{channels}{$channel};
}

1
