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
use 5.010;

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->IRC::configure(%opts);
    return $self;
}

sub _init {
    my $self = shift;
    $self->SUPER::_init(@_);
   
    # data send callback.
    $self->on(send => sub {
        my ($event, $data) = @_;
        $self->connect && return unless $self->transport;
        $self->write_line($data);
    }, name => 'irc.async.send');

}

sub on_read_line;
*on_read_line = *IRC::Parser::handle_data;

sub configure {
    my ($self, %opts) = @_;
    
    # if ssl, use IO::Socket::SSL.
    if ($opts{ssl}) {
        require IO::Socket::SSL;
        my $sock = IO::Socket::SSL->new(
            PeerAddr => $self->{host},
            PeerPort => $self->{port} || 6697,
            Proto    => 'tcp'
        );
        $opts{write_handle} = 
        $opts{read_handle}  = $sock;
    }
    
    # remove libirc options.
    state $keys = [qw(
        host port nick user real pass sasl_user
        sasl_pass enable_raw_events
    )];
    foreach my $key (@$keys) {
        my $val = delete $opts{$key} or next;
        next unless defined $val;
        next if exists $self->{$key};
        $self->{$key} = $val;
    }
    
    $self->SUPER::configure(%opts);

}

sub connect {
    my ($self, %opts) = @_;
    my $on_error   = $opts{on_error} || sub { die }; # lazy

    $self->SUPER::connect(
        host             => $opts{host} || $self->{host},
        service          => $opts{port} || $self->{port} || 6667,
        on_resolve_error => $on_error,
        on_connect_error => $on_error,
        on_connected     => \&login
    );
    
}

sub login {
    my $self = shift;

    # enable UTF-8.
    $self->transport->configure(encoding => 'UTF-8');
    $self->IRC::login();
    
}

1
