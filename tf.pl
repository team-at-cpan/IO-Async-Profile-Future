#!/usr/bin/env perl 
use strict;
use warnings;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;
use IO::Async::Profile::Future;

my $loop = IO::Async::Loop->new;
$loop->add(
	# Keeps running until it goes out of scope, so you'd want to hang onto this object
	# for a while
	my $profile = IO::Async::Profile::Future->new(
	)
);

my $watcher = $profile->create_watcher;
{
	my $f2 = Future->new->label("Future which never resolves");
	my @f;
	for my $type (qw(done fail cancel)) {
		my $v = Future->new->label("should be marked as $type");
		$v->$type(1);
		push @f, $v;
	}
	Future->needs_all(@f)
	 ->label('needs_all')
	 ->on_ready(sub {
		print "needs_all complete\n"
	 });
	Future->wait_any(@f)
	 ->label('wait_any')
	 ->on_ready(sub {
		print "wait_any complete\n"
	 });
	$loop->run;
}
# Explicit discard request for unregistering, although this would
# happen on DESTROY anyway 
$watcher->discard;

=pod

Future map:
* count
* tree nodes
* parent

=cut

