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

use Scalar::Util 'weaken';

# CLASS METHODS

sub new {
    my ($class, $irc, $name) = @_;

    # create a channel object
    $irc->{channels}->{lc $name} = bless my $channel = {
        name   => $name,
        users  => []
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
    my ($irc, $name) = (shift, lc shift);
    $name =~ s/^://;
    return $irc->{channels}->{$name}
}

# lookup by channel name
# or create a new channel if it doesn't exist
sub new_from_name {
    my ($package, $irc, $name) = (shift, shift, lc shift);
    $name =~ s/^://;
    exists $irc->{channels}->{$name} ? $irc->{channels}->{$name} : $package->new($irc, $name)
}

# INSTANCE METHODS

# user is in channel?
sub has_user {
    my ($channel, $user) = @_;
    return 1 if grep { $_ == $user } @{$channel->{users}};
    return
}

# add a user to a channel
sub add_user {
    my ($channel, $user) = @_;
    return if $channel->has_user($user);
    
    # store the user if we haven't already.
    if (!$channel->{irc}{users}{ lc $user->{nick} }) {
        $channel->{irc}{users}{lc $user->{nick} } = $user;
    }
    
    push @{$channel->{users}}, $user;
    $channel->fire_event(user_joined => $user);
}

# remove user from channel
sub remove_user {
    my ($channel, $user) = @_;
    return unless $channel->has_user($user);
    $channel->fire_event(user_remove => $user); # remove, not part, because it might be a quit or something
    @{$channel->{users}} = grep { $_ != $user } @{$channel->{users}};
    
    # if this user has no more channels,
    # TODO: check if the user is being watched/kept track of.
    my @channels = $user->channels;
    if (!scalar @channels) {
        delete $channel->{irc}{users}{lc $user->{nick} };
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
    }
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

1
