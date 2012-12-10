#---------------------------------------------------
# libirc: a flxible event-driven Perl IRC library. |
# ntirc: an insanely flexible Perl IRC client.     |
# simple-relay: a very basic Perl IRC relay bot.   |
# foxy-java: an insanely flexible Perl IRC bot.    |
#                                                  |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012, Mitchell Cooper              |
#                                                  |
# Async.pm: IO::Async::Protocol for libirc socket. |
#---------------------------------------------------
package IRC::Async;

# IO::Async---
# | This class inherits from IRC and IO::Async::Protocol::LineStream. it can be used,
# | with the IO::Async framework simply by ->add'ing it to an IO::Async::Loop and then
# | calling $irc->connect. You do not have to create a socket manually.
# ------------

# clarity-----
# | IRC.pm and Core/Async/IRC.pm are a bit confusing.
# | IRC.pm is the base of the actual IRC class/instance.
# | Core::Async::IRC is based on IRC.pm for asynchronous connections.
# | all IRC objects in ntirc should be objects of Core::Async::IRC,
# | which inherits the methods of IRC.pm.
# ------------

# events------
# | libirc (IRC.pm) is all about events.
# | IO::Async::Notifier (a base of this class) is all about events too.
# | libirc events fired with fire_event; Notifier events are fired with invoke_event.
# | the only Notifier event that ntirc visibly uses here is the on_error event,
# | which may be passed to new().
# ------------

use strict;
use warnings;
use parent qw(IO::Async::Protocol::LineStream IRC);

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->IRC::configure($opts{nick});
    $self->IRC::Handlers::apply_handlers();
    #$self->Handlers::apply_handlers();
    return $self
}

sub on_read_line;
*on_read_line = *IRC::parse_data;

sub configure {
    my ($self, %args) = @_;
    
    # if ssl, use IO::Socket::SSL.
    if ($args{ssl}) {
        require IO::Socket::SSL;
        my $sock = IO::Socket::SSL->new(
            PeerAddr => $self->{temp_host},
            PeerPort => $self->{temp_port} || 6667,
            Proto    => 'tcp'
        );
        $args{write_handle} = 
        $args{read_handle}  = $sock;
    }
    
    foreach my $key (qw|host port nick user real pass|) {
        my $val = delete $args{$key} or next;
        $self->{"temp_$key"} = $val;
    }
    $self->SUPER::configure(%args);
}

sub connect {
    my ($self, %args) = @_;
    my $on_error   = delete $args{on_error} || sub { exit 1 }; # lazy

    $self->SUPER::connect(
        host             => delete $self->{temp_host},
        service          => delete $self->{temp_port} || 6667,
        on_resolve_error => $on_error,
        on_connect_error => $on_error,
        on_connected     => sub { $self->login }
    );
}

sub login {
    my $self = shift;

    # enable UTF-8
    $self->transport->configure(encoding => 'UTF-8');

    my ($nick, $user, $real, $pass) = (
        delete $self->{temp_nick}, 
        delete $self->{temp_user},
        delete $self->{temp_real},
        delete $self->{temp_pass}
    );
    $self->send("PASS $pass") if defined $pass && length $pass;
    $self->send("NICK $nick");
    $self->send("USER $user * * :$real");
}

sub send {
    # IRC.pm's send() isn't actually called, but we can fake it by using this IRC event.
    my $self = shift;
    $self->fire_event(send => @_);
    $self->write_line(@_);
}

1
