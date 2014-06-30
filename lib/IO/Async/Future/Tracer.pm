package IO::Async::Future::Profile;
# ABSTRACT: 
use strict;
use warnings;
use 5.010;
use parent qw(IO::Async::Notifier);

our $VERSION = '0.001';

=head1 NAME

IO::Async::Future::Profile -

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use IO::Async::Future::Profile::Watcher;
use IO::Async::Timer::Periodic;

=head1 METHODS

=cut

sub watcher {
	shift->{watcher} ||= Future::Debug->create_watcher(
		create => sub {
			my $class = __PACKAGE__;
			my ($ev, $f) = @_;
			say "create: " . $class->describe($f);
		},
		on_ready => sub {
			my $class = __PACKAGE__;
			my ($ev, $f) = @_;
			my $elapsed = 1000.0 * (Time::HiRes::time - $f->created);
			$f->elapsed($elapsed);
			say "ready:  " . $class->describe($f);
		},
		destroy => sub {
			my $class = __PACKAGE__;
			my ($ev, $f) = @_;
			my $elapsed = 1000.0 * (Time::HiRes::time - $f->created);
			$f->elapsed($elapsed) unless $f->is_ready;

			my $description = $class->describe($f);
			say "drop:   $description";
			unshift @{$self->old_futures}, $description;
			splice @{$self->old_futures}, 100;
		}
	);
}

sub old_futures { shift->{old_futures} ||= [] }

sub timer {
	shift->{timer} ||= IO::Async::Timer::Periodic->new(
		interval => 1,
		on_tick => sub {
			my $class = __PACKAGE__;
			say "--";
			print "All futures, from oldest to newest:\n";
			for my $f (List::UtilsBy::nsort_by { $_->created } Future::Debug->futures) {
				print "* " . $class->describe($f) . "\n";
			}
			print "Last 100 futures\n";
			for my $f (@{$self->old_futures}) {
				print "* $f\n";
			}
		}
	)
}
sub _add_to_loop {
	my ($self, $loop) = @_;
	$self->add_child($self->timer);
	$self->timer->start;
}

sub describe {
	my ($class, $f) = @_;
	my $now = Time::HiRes::time;
	my $elapsed = 1000.0 * ($now - $f->created);
	my $type = (exists $f->{subs} ? 'dependent' : 'leaf');
	sprintf "%s label [%s] elapsed %.1fms %s",
		$f->_state . ':',
		$f->label,
		$f->is_ready ? $f->elapsed : $elapsed,
		$type . (exists $f->{constructed_at} ? " " . $f->{constructed_at} : '');
}

{
package \
	IO::Async::Future::Profile::Patch;
use Future;
use Time::HiRes ();
use Scalar::Util ();
use List::UtilsBy ();

use Carp qw(cluck);

our %FUTURE_MAP;
our @WATCHERS;

=head1 create_watcher

Returns a new L<Future::Tracer::Watcher>.

=cut

sub create_watcher {
	my $class = shift;
	push @watchers, my $w = Future::Watcher->new;
	$w->subscribe_to_event(@_) if @_;
	# explicit discard
#	Scalar::Util::weaken $watchers[-1];
	$w
}

=head1 delete_watcher

Deletes the given watcher.

=cut

sub delete_watcher {
	my ($class, $w) = @_;
	$w = Scalar::Util::refaddr $w;
	List::UtilsBy::extract_by { Scalar::Util::refaddr($_) eq $w } @watchers;
	()
}

=head1 futures

Returns all the Futures we know about.

=cut

sub futures { grep defined, map $_->{future}, sort values %fm }

sub Future::label {
	my $f = shift;
	return $f->{label} unless @_;
	$f->{label} = shift;
	$f
}
sub Future::created {
	my $f = shift;
	return $f->{created} unless @_;
	$f->{created} = shift || Time::HiRes::time;
	$f
}
sub Future::elapsed {
	my $f = shift;
	return $f->{elapsed} unless @_;
	$f->{elapsed} = shift || Time::HiRes::time;
	$f
}
sub Future::DESTROY {
	my $f = shift;
	# my $f = $destructor->(@_);
	my $entry = delete $fm{$f};
	$_->invoke_event(destroy => $f) for grep defined, @watchers;
	$f
}

BEGIN {
	my $prep = sub {
		my $f = shift;
		if(exists $fm{$f}) {
			$fm{$f}{type} = (exists $f->{subs} ? 'dependent' : 'leaf');
			return $f;
		}
		$f->{constructed_at} = do {
			my $at = Carp::shortmess( "constructed" );
			chomp $at; $at =~ s/\.$//;
			$at
		};

		my $entry = {
			future => $f,
			dependents => [ ],
			type => (exists $f->{subs} ? 'dependent' : 'leaf'),
			nodes => [
			],
		};
		Scalar::Util::weaken($entry->{future});
		$fm{$f} = $entry;
		$f->label('unknown')->created(0);
		my $name = "$f";
		$f->on_ready(sub {
			my $f = shift;
			# cluck "here -> $f";
			$_->invoke_event(on_ready => $f) for grep defined, @watchers;
		});
	};

	my %map = (
		new => sub {
			my $constructor = shift;
			sub {
				my $f = $constructor->(@_);
				$prep->($f);
				$_->invoke_event(create => $f) for grep defined, @watchers;
				$f
			};
		},
		_new_dependent => sub {
			my $constructor = shift;
			sub {
				my @subs = @{$_[1]};
				my $f = $constructor->(@_);
				$prep->($f);
				my $entry = $fm{$f};
				# Inform subs that they have a new parent
				for(@subs) {
					die "missing fm for $_?" unless exists $fm{$_};
					push @{$fm{$_}{dependents}}, $f;
					Scalar::Util::weaken($fm{$_}{dependents}[-1]);
				}
				$_->invoke_event(create => $f) for grep defined, @watchers;
				$f
			};
		},
	);

	for my $k (keys %map) {
		my $orig = Future->can($k);
		my $code = $map{$k}->($orig);
		{
			no strict 'refs';
			no warnings 'redefine';
			*{'Future::' . $k} = $code;
		}
	}
}
}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

