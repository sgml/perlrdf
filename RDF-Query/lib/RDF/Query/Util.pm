# RDF::Query::Util
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Util - Miscellaneous utility functions to support work with RDF::Query.

=head1 SYNOPSIS

 use RDF::Query::Util;
 my $query = &RDF::Query::Util::cli_make_query;
 my $model = &RDF::Query::Util::cli_make_model;
 $query->execute( $model );
 ...

=head1 FUNCTIONS

=over 4

=cut

package RDF::Query::Util;

use strict;
use warnings;
no warnings 'redefine';
use Carp qw(carp croak confess);

use URI::file;
use RDF::Query;
use LWP::Simple;

=item C<< cli_make_query >>

Returns a RDF::Query object based on the arguments in @ARGV. These arguments
are parsed using C<< &cli_parse_args >>. If the -e flag is not present, the
query will be loaded from a file named by the argument in @ARGV immediately
following the final argument parsed by C<< &cli_parse_args >>.

=cut

sub cli_make_query {
	my %args	= cli_parse_args();
	my $class	= delete $args{ class };
	my $sparql	= delete $args{ query };
	my $l		= Log::Log4perl->get_logger("rdf.query.util");
	$l->debug("creating sparql query with class $class");
	my $query	= $class->new( $sparql, \%args );
	
	if ($args{ service_descriptions }) {
		$query->add_service( $_ ) for (@{ $args{ service_descriptions } });
	}
	
	return $query;
}

=item C<< cli_make_model >>

Calls C<< make_model >> with arguments from C<< @ARGV >>, returning the
constructed model object.

C<< cli_make_model >> will usually be called after cli_make_query, allowing a
typical CLI invocation to look like `prog.pl [flags] [query file] [data files]`.

=cut

sub cli_make_model {
	return make_model( @ARGV );
}

=item C<< make_model ( @files ) >>

Returns a model object suitable for use in a call to C<< $query->execute >>,
loaded with RDF from files and/or URLs listed in @files. This model may be any
of the supported models, but as currently implemented will be a
RDF::Trine::Model object.

=cut

sub make_model {
	my $l		= Log::Log4perl->get_logger("rdf.query.util");
	
	# create a temporary triplestore, and wrap it into a model
	my $store	= RDF::Trine::Store::DBI->temporary_store();
	my $model	= RDF::Trine::Model->new( $store );
	
	# read in the list of files with RDF/XML content for querying
	my @files	= @_;
	
	# create a rdf/xml parser object that we'll use to read in the rdf data
	my $parser	= RDF::Trine::Parser->new('rdfxml');
	
	# loop over all the files
	foreach my $i (0 .. $#files) {
		my $file	= $files[ $i ];
		if ($file =~ m<^https?:\/\/>) {
			$l->debug("fetching RDF from $file ...");
			my $uri		= URI->new( $file );
			my $content	= get($file);
			$parser->parse_into_model( $uri, $content, $model );
		} else {
			$file	= File::Spec->rel2abs( $file );
			# $uri is the URI object used as the base uri for parsing
			my $uri		= URI::file->new_abs( $file );
			my $content	= do { open( my $fh, '<', $file ); local($/) = undef; <$fh> };
			$parser->parse_into_model( $uri, $content, $model );
		}
	}
	return $model;
}

=item C<< cli_parse_args >>

Parses CLI arguments from @ARGV and returns a HASH with the recognized key/values.
The allowable arguments are listed below.

=cut

sub cli_parse_args {
	my %args;
	$args{ class }	= 'RDF::Query';
	my @service_descriptions;
	
	return unless (@ARGV);
	while ($ARGV[0] =~ /^-(\w+)$/) {
		my $opt	= shift(@ARGV);
		if ($opt eq '-e') {
			$args{ query }	= shift(@ARGV);
		} elsif ($opt eq '-l') {
			$args{ lang }	= shift(@ARGV);
		} elsif ($opt eq '-O') {
			$args{ optimize }	= 1;
		} elsif ($opt eq '-o') {
			$args{ force_no_optimization }	= 1;
		} elsif ($opt eq '-c') {
			my $class		= shift(@ARGV);
			eval "require $class";
			$args{ class }	= $class;
		} elsif ($opt eq '-f') {
			require RDF::Query::Federate;
			$args{ class }	= 'RDF::Query::Federate';
		} elsif ($opt eq '-F') {
			require RDF::Query::Federate;
			require RDF::Query::ServiceDescription;
			$args{ class }	= 'RDF::Query::Federate';
			my $url_string	= shift(@ARGV);
			my $uri;
			if ($url_string =~ m<^https?:\/\/>) {
				$uri		= URI->new( $url_string );
			} else {
				$uri		= URI::file->new_abs( $url_string );
			}
			my $sd	= RDF::Query::ServiceDescription->new_from_uri( $uri );
			push(@service_descriptions, $sd);	
		}
	}
	
	if (@service_descriptions) {
		$args{ service_descriptions }	= \@service_descriptions;
	}
	
	unless (defined($args{query})) {
		my $file	= shift(@ARGV);
		my $sparql	= ($file eq '-')
					? do { local($/) = undef; <> }
					: do { local($/) = undef; open(my $fh, '<', $file) || die $!; binmode($fh, ':utf8'); <$fh> };
		$args{ query }	= $sparql;
	}
	return %args;
}

=item C<< start_endpoint ( $model, $port ) >>

Starts an SPARQL endpoint HTTP server on port $port.

If called in list context, returns the PID and the actual port the server bound
to. If called in scalar context, returns only the port.

=cut

sub start_endpoint {
	my $model	= shift;
	my $port	= shift;
	my $path	= shift;
	
	require CGI;
	require RDF::Endpoint::Server;
	
	local($ENV{TMPDIR})	= '/tmp';
	my $cgi	= CGI->new;
	my $s	= RDF::Endpoint::Server->new_with_model( $model,
				Port		=> $port,
				Prefix		=> '',
				CGI			=> $cgi,
				IncludePath	=> $path,
			);
	
	my $pid	= $s->background();
#	warn "Endpoint started as [$pid]\n";
	if (wantarray) {
		return ($pid, $port);
	} else {
		return $port;
	}
}

1;

__END__

=back

=head1 COMMAND LINE ARGUMENTS

=over 4

=item -e I<str>

Specifies the query string I<str>.

=item -l I<lang>

Specifies the query language I<lang> used. This should be one of: B<sparql>,
B<sparqlp>, or B<rdql>.

=item -O

Turns on optimization.

=item -o

Turns off optimization.

=item -c I<class>

Specifies the perl I<class> used to construct the query object. Defaults to
C<< RDF::Query >>.

=item -f

Implies -c B<RDF::Query::Federate>.

=item -F I<loc>

Species the URL or path to a file I<loc> which contains an RDF service
description. The described service is used as an underlying triplestore for
query answering. Implies -f.

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut