# RDF::Query::Plan::Join::NestedLoop
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Plan::Join::NestedLoop - Executable query plan for nested loop joins.

=head1 METHODS

=over 4

=cut

package RDF::Query::Plan::Join::NestedLoop;

use strict;
use warnings;
use base qw(RDF::Query::Plan::Join);
use Scalar::Util qw(blessed);
use Data::Dumper;

BEGIN {
	$RDF::Query::Plan::Join::JOIN_CLASSES{ 'RDF::Query::Plan::Join::NestedLoop' }++;
}

use RDF::Query::ExecutionContext;
use RDF::Query::VariableBindings;

=item C<< new ( $lhs, $rhs ) >>

=cut

sub new {
	my $class	= shift;
	my $lhs		= shift;
	my $rhs		= shift;
	my $opt		= shift || 0;
	my $self	= $class->SUPER::new( $lhs, $rhs, $opt );
	return $self;
}

=item C<< execute ( $execution_context ) >>

=cut

sub execute ($) {
	my $self	= shift;
	my $context	= shift;
	if ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "NestedLoop join plan can't be executed while already open";
	}
	
	my @inner;
	$self->rhs->execute( $context );
	while (my $row = $self->rhs->next) {
#		warn "*** loading inner row cache with: " . Dumper($row);
		push(@inner, $row);
	}
	$self->lhs->execute( $context );
	if ($self->lhs->state == $self->OPEN) {
		$self->[0]{inner}			= \@inner;
		$self->[0]{outer}			= $self->lhs;
		$self->[0]{inner_index}		= 0;
		$self->[0]{needs_new_outer}	= 1;
		$self->[0]{inner_count}		= 0;
		$self->state( $self->OPEN );
	} else {
		warn "no iterator in execute()";
	}
#	warn '########################################';
	$self;
}

=item C<< next >>

=cut

sub next {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "next() cannot be called on an un-open NestedLoop join";
	}
	my $outer	= $self->[0]{outer};
	my $inner	= $self->[0]{inner};
	my $opt		= $self->[3];
	
	while (1) {
		if ($self->[0]{needs_new_outer}) {
			$self->[0]{outer_row}	= $outer->next;
			if (ref($self->[0]{outer_row})) {
				$self->[0]{needs_new_outer}	= 0;
				$self->[0]{inner_index}		= 0;
				$self->[0]{inner_count}		= 0;
				use Data::Dumper;
	#			warn "got new outer row: " . Dumper($self->[0]{outer_row});
			} else {
				# we've exhausted the outer iterator. we're now done.
	#			warn "exhausted";
				return undef;
			}
		}
		
		while ($self->[0]{inner_index} < scalar(@$inner)) {
			my $inner_row	= $inner->[ $self->[0]{inner_index}++ ];
	#		warn "using inner row: " . Dumper($inner_row);
			if (my $joined = $inner_row->join( $self->[0]{outer_row} )) {
#				warn "-> joined\n";
				$self->[0]{inner_count}++;
				return $joined;
			} else {
#				warn "-> didn't join\n";
			}
		}
		
		$self->[0]{needs_new_outer}	= 1;
		if ($opt and $self->[0]{inner_count} == 0) {
			return $self->[0]{outer_row};
		}
	}
}

=item C<< close >>

=cut

sub close {
	my $self	= shift;
	unless ($self->state == $self->OPEN) {
		throw RDF::Query::Error::ExecutionError -text => "close() cannot be called on an un-open NestedLoop join";
	}
	delete $self->[0]{inner};
	delete $self->[0]{outer};
	delete $self->[0]{inner_index};
	delete $self->[0]{needs_new_outer};
	delete $self->[0]{inner_count};
	$self->lhs->close();
	$self->rhs->close();
	$self->SUPER::close();
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut