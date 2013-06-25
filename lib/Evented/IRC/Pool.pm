#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# Copyright (c) 2012-13, Mitchell Cooper           |
#---------------------------------------------------
package Evented::IRC::Pool;

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

########################
### MANAGING SERVERS ###
########################

# get server by ID or name.
sub get_server {
    my ($pool, $id_or_name) = @_;
    return unless defined $id_or_name;
    return $pool->{servers}{$id_or_name} if defined $pool->{servers}{$id_or_name};
    return defined $pool->{snames}{lc $id_or_name}      ?
    $pool->{servers}{ $pool->{snames}{lc $id_or_name} } : undef;
}

# add a server to the pool.
sub add_server {
    my ($pool, $server) = @_;
    return $server if exists $server->{id} && $pool->{servers}{$server};
    
    # use the next available ID.
    my $id = $server->{id} = $pool->_next_server_id;
    
    # weakly reference to the server.
    # this will be strengthened when the server is retained.
    $pool->{servers}{$id}     = $server;
    $pool->{ref_count}{$id} = 0;
    weaken($pool->{servers}{$id});
    
    # reference to the pool.
    $server->{pool} = $pool;
        
    # store the server name.
    $pool->{snames}{ lc $server->{name} } = $id;
    
    # make the IRC object a listener.
    $server->add_listener($pool->irc, 'server');
    
    return $server;
}

# remove a server from the pool.
sub remove_server {
    my ($pool, $server) = @_;
    return unless $pool->{servers}{$server};
    
    delete $pool->{snames}{ lc $server->{name} };
    delete $pool->{servers}{$server};
    
    return 1;
}

# change a server's name.
sub set_server_name {
    my ($pool, $server, $old_name, $name) = @_;
    delete $pool->{snames}{lc $old_name};
    $pool->{snames}{lc $name} = $server;
}

# fetch next available server ID.
sub _next_server_id {
    my $pool = shift;
    $pool->{_sid} ||= 0;
    return $pool->irc->id.$pool->{_sid}++.q(s);
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
    
    # make the IRC object a listener.
    $channel->add_listener($pool->irc, 'channel');

    return $channel;
}

# remove a channel from the pool.
sub remove_channel {
    my ($pool, $channel) = @_;
    delete $pool->{channels}{$channel};
}

######################
### MANAGING USERS ###
######################

# if the passed value starts with a number, it is assumed to be
# a user ID, and the method will return a user with that ID.
# if it does not start with a number, it is assumed to be the
# user's nickname, and a user with that nickname will be returned.
sub get_user {
    my ($pool, $id_or_nick) = @_;
    return unless defined $id_or_nick;
    return $pool->{users}{$id_or_nick} if defined $pool->{users}{$id_or_nick};
    return defined $pool->{nicks}{lc $id_or_nick}    ?
    $pool->{users}{ $pool->{nicks}{lc $id_or_nick} } : undef;
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

# change a user's nickname.
sub set_user_nick {
    my ($pool, $user, $old_nick, $nick) = @_;
    delete $pool->{nicks}{lc $old_nick};
    $pool->{nicks}{lc $nick} = $user;
}

# fetch next available user ID.
sub _next_user_id {
    my $pool = shift;
    $pool->{_uid} ||= 0;
    return $pool->irc->id.$pool->{_uid}++.q(u);
}

##################
### REFERENCES ###
##################

# increase reference count.
sub retain {
    my ($pool, $obj, $comment) = @_;
    my $refcount = ++$pool->{ref_count}{$obj};
    
    # add comment.
    if (defined $comment) {
        $pool->{comments}{$obj} ||= [];
        push @{ $pool->{comments}{$obj} }, $comment;
    }
    
    return $refcount if $refcount != 1;
    
    # refcount has been incremented to one.
    # store the object semi-permanently.

    # re-reference.
    my $type = _type_of($obj);
    delete $pool->{$type}{$obj};
    $pool->{$type}{$obj} = $obj;
    
    return 1;
}

# decrease reference count.
sub release {
    my ($pool, $obj, $comment) = @_;
    my $refcount = --$pool->{ref_count}{$obj};
    
    # remove comment.
    if ($pool->{comments}{$obj} && defined $comment) {
        @{ $pool->{comments}{$obj} } = grep { $_ ne $comment } @{ $pool->{comments}{$obj} };
    }
    
    return $refcount if $refcount;

    # refcount is zero.
    # we should now weaken our reference.
    my $type = _type_of($obj);
    weaken($pool->{$type}{$obj});

    return 0;
}

# fetch reference count.
sub refcount {
    my ($pool, $obj) = @_;
    return $pool->{ref_count}{$obj} || 0;
}

# fetch reference comments.
sub references {
    my ($pool, $obj) = @_;
    return @{ $pool->{comments}{$obj} || [] };
}

sub _type_of {
    my $obj = shift;
    my $type = 'objects';
    $type = 'users'    if $obj->isa('Evented::IRC::User');
    $type = 'channels' if $obj->isa('Evented::IRC::Channel');
    $type = 'servers'  if $obj->isa('Evented::IRC::Server');
    return $type;
}

1
