package IO::Async::Future::Tracer;

use strict;
use warnings;
use parent qw(Mixin::Event::Dispatch);

our $VERSION = '0.001';

=head1 NAME

IO::Async::Future::Tracer::Watcher - event dispatcher for L<IO::Async::Future::Tracer>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut

sub new { my $class = shift; bless { @_ }, $class }

sub discard {
	my $self = shift;
	Future::Debug->delete_watcher($self)
}


1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.


