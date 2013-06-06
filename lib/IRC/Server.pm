#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
#---------------------------------------------------
package IRC::Server;

use warnings;
use strict;
use parent qw(EventedObject IRC::Functions::Server);
use 5.010;

use overload
    '""'     => sub { shift->{id} },            # string context  = ID
    '0+'     => sub { shift },                  # numeric context = memory address 
    'bool'   => sub { 1 },                      # boolean context = true
    '${}'    => sub { \shift->{name} },         # scalar deref    = name
    '~~'     => \&_match,                       # smart match
    fallback => 1;

use Scalar::Util qw(blessed weaken);

#####################
### CLASS METHODS ###
#####################

sub new {
    my ($class, %opts) = @_;

    # create a new server object.
    bless my $server = {
        %opts
    }, $class;
    
    # assign a temporary identifier.
    $server->{name} = 'libirc.pseudoserver('.($server + 0).')';
    $server->{id}   = '[Server '.($server + 0).q(]);

    return $server;
}

######################
### SERVER SUPPORT ###
######################

# determine if the server suppots a particular capability.
sub has_cap {
    my ($server, $cap) = @_;
    return $server->{available_cap}{lc $cap};
}

# determine if the server has a capability enabled.
sub cap_enabled {
    my ($server, $cap) = @_;
    return $server->{active_cap}{lc $cap};
}

# set a capability as available.
sub set_cap_available {
    my ($server, $cap) = @_;
    $server->{available_cap}{lc $cap} = 1;
}

# set a capability as enabled.
sub set_cap_enabled {
    my ($server, $cap) = @_;
    $server->{active_cap}{lc $cap} = 1;
}

# fetch server support information.
sub support {
    my ($server, $support) = @_;
    return $server->{support}{lc $support};
}

# set server support information.
sub set_support {
    my ($server, $support, $value) = @_;
    $server->{support}{lc $support} = defined $value ? $value : 1;
}

# fetch the network name from the perspective of the server.
sub network_name {
    return shift->support('network');
}

# set a prefix mode.
sub set_prefix {
    my ($server, $level, $prefix, $mode) = @_;
    $server->{prefix}{$level} = [$prefix, $mode];
}

# fetch mode of a prefix.
sub prefix_to_mode {
    my ($server, $prefix) = @_;
    foreach my $level (keys %{$server->{prefix}}) {
        return $server->{prefix}{$level}[1]
        if $server->{prefix}{$level}[0] eq $prefix;
    }
    return;
}

# fetch prefix of a mode.
sub mode_to_prefix {
    my ($server, $mode) = @_;
    foreach my $level (keys %{$server->{prefix}}) {
        return $server->{prefix}{$level}[0]
        if $server->{prefix}{$level}[1] eq $mode;
    }
    return;
}

# prefix to level.
sub prefix_to_level {
    my ($server, $prefix) = @_;
    foreach my $level (keys %{$server->{prefix}}) {
        return $level
        if $server->{prefix}{$level}[0] eq $prefix;
    }
    return;
}

######################
### MANAGING USERS ###
######################

# return array of users on server.
sub users {
    return values %{ shift->{users} };
}

# check if user belongs to server.
sub has_user {
    my ($server, $user) = @_;
    return exists $server->{users}{$user};
}

# add a user to the server.
sub add_user {
    my ($server, $user) = @_;
    return if $server->has_user($user);
    
    # add user to server.
    weaken($server->{users}{$user} = $user);
    $user->{server} = $server->id;
   
    # hold on to the server.
    $server->pool->retain($server, "user:$user:on_server");

    $server->fire_event(user_add => $user);
}

# remove a user from the server.
sub remove_user {
    my ($server, $user) = @_;
    return unless $server->has_user($user);
    
    EventedObject::fire_events_together(
        [ $server,  user_remove     =>  $user    ],
        [ $user,    remove_server   =>  $server  ]
    );
    
    delete $server->{users}{$user};
    delete $user->{server};
    
    # let go of the server.
    $server->pool->release($server, "user:$user:on_server"); 
    
    return 1;
}

#########################
### INTERNAL ROUTINES ###
#########################

sub id     { shift->{id}      }
sub irc    { shift->pool->irc }
sub pool   { shift->{pool}    }
sub server { shift->{server}  }

# smart matching
sub _match {
    # TODO.
    
    return;
}

sub DESTROY {
    my $server = shift;

    # remove all users from server.
    $server->remove_user($_) foreach $server->users;

    # if the server belongs to a pool, remove it.
    $server->pool->remove_server($server) if $server->pool;
    
}


1
