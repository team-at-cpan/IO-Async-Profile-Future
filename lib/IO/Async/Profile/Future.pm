package IO::Async::Profile::Future;
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

use IO::Async::Timer::Periodic;
use curry::weak;
use List::UtilsBy qw(nsort_by);

=head1 METHODS

=cut

sub future_created_event {
	my ($self, $ev, $f) = @_;
	$self->debug_printf("create: %s", $self->describe($f));
}

sub future_ready_event {
 	my $self = shift;
	my ($ev, $f) = @_;
	my $elapsed = 1000.0 * (Time::HiRes::time - $f->created);
	$f->elapsed($elapsed);
	$self->debug_printf("ready: %s", $self->describe($f));
}
sub future_destroy_event {
	my $self = shift;
	my ($ev, $f) = @_;
	my $elapsed = 1000.0 * (Time::HiRes::time - $f->created);
	$f->elapsed($elapsed) unless $f->is_ready;

	my $description = $self->describe($f);
	$self->debug_printf("drop: %s", $description);
	unshift @{$self->old_futures}, $description;
	splice @{$self->old_futures}, 100;
}

sub create_watcher {
	my $self = shift;
	$self->{watcher} ||= IO::Async::Future::Profile::Patch->create_watcher(
		create => $self->curry::weak::future_created_event,
		on_ready => $self->curry::weak::future_ready_event,
		destroy => $self->curry::weak::future_destroy_event,
	);
}

sub old_futures { shift->{old_futures} ||= [] }

sub timer_event {
	my $self = shift;
	$self->debug_printf("All futures, from oldest to newest");
	for my $f (nsort_by { $_->created } IO::Async::Future::Profile::Patch->futures) {
		$self->debug_printf("* %s", $self->describe($f));
	}
	$self->debug_printf("Last 100 futures");
	for my $f (@{$self->old_futures}) {
		$self->debug_printf("* %s", $f);
	}
}

sub timer_interval { 1 }

sub timer {
	my $self = shift;
	$self->{timer} ||= IO::Async::Timer::Periodic->new(
		interval => $self->timer_interval,
		on_tick => $self->curry::weak::timer_event,
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
package
	IO::Async::Future::Profile::Patch;
use Future;
use Time::HiRes ();
use Scalar::Util ();
use List::UtilsBy ();

use Carp qw(cluck);

our %FUTURE_MAP;
our @WATCHERS;

=head1 create_watcher

Returns a new watcher instance.

=cut

sub create_watcher {
	my $self = shift;
	push @WATCHERS, my $w = IO::Async::Future::Profile::Watcher->new;
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
	List::UtilsBy::extract_by { Scalar::Util::refaddr($_) eq $w } @WATCHERS;
	()
}

=head1 futures

Returns all the Futures we know about.

=cut

sub futures { grep defined, map $_->{future}, sort values %FUTURE_MAP }

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
	my $entry = delete $FUTURE_MAP{$f};
	$_->invoke_event(destroy => $f) for grep defined, @WATCHERS;
	$f
}

BEGIN {
	my $prep = sub {
		my $f = shift;
		if(exists $FUTURE_MAP{$f}) {
			$FUTURE_MAP{$f}{type} = (exists $f->{subs} ? 'dependent' : 'leaf');
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
		$FUTURE_MAP{$f} = $entry;
		$f->label('unknown')->created(0);
		my $name = "$f";
		$f->on_ready(sub {
			my $f = shift;
			# cluck "here -> $f";
			$_->invoke_event(on_ready => $f) for grep defined, @WATCHERS;
		});
	};

	my %map = (
		new => sub {
			my $constructor = shift;
			sub {
				my $f = $constructor->(@_);
				$prep->($f);
				$_->invoke_event(create => $f) for grep defined, @WATCHERS;
				$f
			};
		},
		_new_dependent => sub {
			my $constructor = shift;
			sub {
				my @subs = @{$_[1]};
				my $f = $constructor->(@_);
				$prep->($f);
				my $entry = $FUTURE_MAP{$f};
				# Inform subs that they have a new parent
				for(@subs) {
					die "missing fm for $_?" unless exists $FUTURE_MAP{$_};
					push @{$FUTURE_MAP{$_}{dependents}}, $f;
					Scalar::Util::weaken($FUTURE_MAP{$_}{dependents}[-1]);
				}
				$_->invoke_event(create => $f) for grep defined, @WATCHERS;
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
{
package
	IO::Async::Future::Profile::Watcher;

use strict;
use warnings;
use parent qw(Mixin::Event::Dispatch);

sub new { my $class = shift; bless { @_ }, $class }

sub discard {
	my $self = shift;
	IO::Async::Future::Profile::Patch->delete_watcher($self)
}

}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

