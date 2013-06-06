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

use Scalar::Util 'blessed';

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


sub id     { shift->{id}      }
sub irc    { shift->pool->irc }
sub pool   { shift->{pool}    }
sub server { shift->{server}  }

# smart matching
sub _match {
    # TODO.
    
    return;
}

sub users { }

sub has_user { }

sub add_user { }

sub remove_user { }

sub DESTROY {
    my $server = shift;

    # if the server belongs to a pool, remove it.
    $server->pool->remove_server($server) if $server->pool;
    
}


1
