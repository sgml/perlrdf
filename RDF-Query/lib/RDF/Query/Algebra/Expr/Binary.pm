# RDF::Query::Algebra::Expr::Binary
# -------------
# $Revision: 121 $
# $Date: 2006-02-06 23:07:43 -0500 (Mon, 06 Feb 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Expr::Binary - Algebra class for binary expressions

=cut

package RDF::Query::Algebra::Expr::Binary;

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::Algebra::Expr);

use Data::Dumper;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);
use Carp qw(carp croak confess);

######################################################################

our ($VERSION, $debug, $lang, $languri);
BEGIN {
	$debug		= 0;
	$VERSION	= do { my $REV = (qw$Revision: 121 $)[1]; sprintf("%0.3f", 1 + ($REV/1000)) };
}

######################################################################

=head1 METHODS

=over 4

=cut

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	my $context	= shift;
	
	return sprintf(
		'(%s %s %s)',
		$self->op,
		map { $_->sse( $context ) } $self->operands,
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $context	= shift;
	my $indent	= shift;
	my $op		= $self->op;
	return sprintf("(%s $op %s)", map { $_->as_sparql( $context, $indent ) } $self->operands);
}


=item C<< evaluate ( $query, $bridge, \%bound ) >>

Evaluates the expression using the supplied context (bound variables and bridge
object). Will return a RDF::Query::Node object.

=cut

sub evaluate {
	my $self	= shift;
	my $query	= shift;
	my $bridge	= shift;
	my $bound	= shift;
	my $op		= $self->op;
	my @operands	= $self->operands;
	my ($lhs, $rhs)	= map {
						$_->isa('RDF::Query::Algebra')
							? $_->evaluate( $query, $bridge, $bound )
							: ($_->isa('RDF::Query::Node::Variable'))
								? $bound->{ $_->name }
								: $_
	} @operands;
	
	warn "Binary Operator '$op': " . Dumper($lhs, $rhs) if ($debug);
	
	if ($op =~ m#^[-+/*]$#) {
		my $type	= $self->promote_type( $op, $lhs, $rhs );
		my $value;
		if ($op eq '+') {
			$value	= $lhs->numeric_value + $rhs->numeric_value;
		} elsif ($op eq '-') {
			$value	= $lhs->numeric_value - $rhs->numeric_value;
		} elsif ($op eq '*') {
			$value	= $lhs->numeric_value * $rhs->numeric_value;
		} elsif ($op eq '/') {
			$value	= $lhs->numeric_value / $rhs->numeric_value;
		} else {
			die;
		}
		return RDF::Query::Node::Literal->new( $value, undef, $type );
	} elsif ($op =~ m#^([<>]=?)|!?=$#) {
		my @types	= qw(RDF::Query::Node::Literal RDF::Query::Node::Resource RDF::Query::Node::Blank);
		
		if ($op =~ /[<>]/) {
			# if it's a relational operation other than equality testing,
			# the two nodes must be of the same type.
			my $ok		= 0;
			foreach my $type (@types) {
				$ok	||= 1 if ($lhs->isa($type) and $rhs->isa($type));
			}
			if (not($ok) and not($RDF::Query::Node::Literal::LAZY_COMPARISONS)) {
				throw RDF::Query::Error::TypeError -text => "Attempt to compare two nodes of different types.";
			}
		}
		
		my $bool;
		if ($op eq '<') {
			$bool	= ($lhs < $rhs);
		} elsif ($op eq '<=') {
			$bool	= ($lhs <= $rhs);
		} elsif ($op eq '>') {
			$bool	= ($lhs > $rhs);
		} elsif ($op eq '>=') {
			$bool	= ($lhs >= $rhs);
		} elsif ($op eq '==') {
			$bool	= ($lhs == $rhs);
		} elsif ($op eq '!=') {
			$bool	= ($lhs != $rhs);
		} else {
			die;
		}
		
		my $value	= ($bool) ? 'true' : 'false';
		warn "-> $value\n" if ($debug);
		return RDF::Query::Node::Literal->new( $value, undef, 'http://www.w3.org/2001/XMLSchema#boolean' );
	} else {
		die
	}
}

my $xsd				= 'http://www.w3.org/2001/XMLSchema#';
my %integer_types	= map { join('', $xsd, $_) => 1 } qw(nonPositiveInteger nonNegativeInteger positiveInteger negativeInteger short unsignedShort byte unsignedByte long unsignedLong);
my %rel	= (
	"${xsd}integer"				=> 0,
	"${xsd}int"					=> 1,
	"${xsd}unsignedInt"			=> 2,
	"${xsd}nonPositiveInteger"	=> 3,
	"${xsd}nonNegativeInteger"	=> 4,
	"${xsd}positiveInteger"		=> 5,
	"${xsd}negativeInteger"		=> 6,
	"${xsd}short"				=> 7,
	"${xsd}unsignedShort"		=> 8,
	"${xsd}byte"				=> 9,
	"${xsd}unsignedByte"		=> 10,
	"${xsd}long"				=> 11,
	"${xsd}unsignedLong"		=> 12,
	"${xsd}decimal"				=> 13,
	"${xsd}float"				=> 14,
	"${xsd}double"				=> 15,
);

=item C<< promote_type ( $op, $lhs, $rhs ) >>

Returns the XSD type URI (as a string) for the resulting value of performing the
supplied operation on the arguments.

=cut

sub promote_type {
	my $self	= shift;
	my $op		= shift;
	no warnings 'uninitialized';
	my @types	= sort { $rel{$b} <=> $rel{$a} } map { $_->literal_datatype } @_;
	
	my $type	= $types[0];
	$type		= "${xsd}integer" if ($integer_types{ $type });
	return $type;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut