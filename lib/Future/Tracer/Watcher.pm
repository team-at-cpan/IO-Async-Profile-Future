package Future::Tracer::Watcher;

use strict;
use warnings;
use parent qw(Mixin::Event::Dispatch);

sub new { my $class = shift; bless { @_ }, $class }

sub discard {
	my $self = shift;
	Future::Debug->delete_watcher($self)
}

1;

