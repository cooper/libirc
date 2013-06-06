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
        name => 'libirc.pseudoserver', # default
        %opts
    }, $class;
    
    # assign a temporary identifier.
    $server->{id} = '[Server '.($server + 0).q(]);

    return $server;
}

########################
### INSTANCE METHODS ###
########################


sub users { }

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


sub id     { shift->{id}      }
sub irc    { shift->pool->irc }
sub pool   { shift->{pool}    }
sub server { shift->{server}  }

# array of users.
sub users {
    return values %{ shift->{users} };
}

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
