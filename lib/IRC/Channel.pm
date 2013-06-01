#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# ntirc: an insanely flexible IRC client.          |
# foxy: an insanely flexible IRC bot.              |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Copyright (c) 2012-13, Mitchell Cooper           |
# Channel.pm: the channel object class.            |
#---------------------------------------------------
package IRC::Channel;

use warnings;
use strict;
use parent qw(EventedObject IRC::Functions::Channel);
use overload
    '""'     => sub { shift->{id} },                    # string context  = ID
    '0+'     => sub { shift },                          # numeric context = memory address 
    'bool'   => sub { 1 },                              # boolean context = true
    '${}'    => sub { \shift->{name} },                 # scalar deref    = name
    '@{}'    => sub { [ values %{shift->{users}} ] },   # array deref     = users
    fallback => 1;

use Scalar::Util 'weaken';

# CLASS METHODS

sub new {
    my ($class, $irc, $name) = @_;
    
    # create a channel object
    $irc->{channels}->{lc $name} = bless my $channel = {
        name   => $name,
        users  => {},
        id     => lc $name
    };

    # reference weakly to the IRC object.
    $channel->{irc} = $irc;
    weaken($channel->{irc});

    # make the IRC object a listener.
    $channel->add_listener($channel, 'channel');

    # fire new channel event
    $channel->fire_event(new => $channel);

    return $channel;
}

# lookup by channel name
sub from_name {
    my ($irc, $lcname) = (shift, lc shift);
    $lcname =~ s/^://;
    return $irc->{channels}->{$lcname}
}

# lookup by channel name
# or create a new channel if it doesn't exist
sub new_from_name {
    my ($package, $irc, $name) = @_;
    $name =~ s/^://;
    exists $irc->{channels}->{lc $name} ? $irc->{channels}->{lc $name} : $package->new($irc, $name);
}

# INSTANCE METHODS

# user is in channel?
sub has_user {
    my ($channel, $user) = @_;
    return exists $channel->{users}{$user->id};
}

# add a user to a channel
sub add_user {
    my ($channel, $user) = @_;
    return if $channel->has_user($user);
    
    # add user to channel.
    $channel->{users}{$user->id} = $user;
    
    # add channel to user.
    # hold a weak reference to the channel.
    $user->{channels}{$channel->id} = $channel;
    weaken($user->{channels}{$channel->id});
    
    $channel->fire_event(user_joined => $user);
}

# remove user from channel
sub remove_user {
    my ($channel, $user) = @_;
    return unless $channel->has_user($user);
    
    $channel->fire_event(user_remove => $user);
    
    delete $channel->{users}{$user->id};
    delete $user->{channels}{$channel->id};
    
    # if this user has no more channels,
    # TODO: check if the user is being watched/kept track of.
    my @channels = $user->channels;
    if (!scalar @channels) {
        delete $channel->{irc}{users}{$user->nick};
    }
    
    return 1;
}

# change the channel topic
sub set_topic {
    my ($channel, $topic, $setter, $time) = @_;

    # fire a "changed" event
    # but not if this is the first time the topic has been set
    $channel->fire_event(topic_changed => $topic, $setter, $time) if exists $channel->{topic};

    $channel->{topic} = {
        topic  => $topic,
        setter => $setter,
        time   => $time
    };
}

# set a user's channel status
sub set_status {
    my ($channel, $user, $level) = @_;

    # add the user to the status array
    push @{$channel->{status}->{$level}}, $user;

    # fire event
    $channel->fire_event(set_user_status => $user, $level);
}

# get status(es) of a user
sub user_status {
    my ($channel, $user) = @_;
    my @status;
    foreach my $level (keys %{$channel->{status}}) {
        foreach my $this_user (@{$channel->{status}->{$level}}) {
            push @status, $level if $user == $this_user
        }
    }
    return @status
}

# user is status or higher?
sub user_is_status {
    my ($channel, $user, $need) = @_;
    foreach my $level (keys %{$channel->{status}}) {
        foreach my $this_user (@{$channel->{status}->{$level}}) {
            next unless $level >= $need;
            return 1 if $user == $this_user;
        }
    }
    return
}

# returns an array of users in the channel.
sub users {
    return values %{ shift->{users} };
}

sub id { shift->{id} }

1
