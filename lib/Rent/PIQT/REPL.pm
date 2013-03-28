package Rent::PIQT::REPL;

use Moo;

# Reference to cache handler. Required, defaults to memory cache.
has 'cache' => (is => 'rw', isa => 'Rent::PIQT::Cache',
        required => 1, trigger => \&_set_controller);

# Configuration container. Required, defaults to empty config.
has 'config' => (is => 'rw', isa => 'Rent::PIQT::Config',
        required => 1, trigger => \&_set_controller);

# Database handler to support multiple database dialects. Required, but no
# default is provided.
has 'db' => (is => 'rw', isa => 'Rent::PIQT::DB',
        required => 1, trigger => \&_set_controller);

# Output handler to support multiple output formats. Required, defaults to
# tab-delimited format.
has 'output' => (is => 'rw', isa => 'Rent::PIQT::Output', lazy_build => 1,
        required => 1, trigger => \&_set_controller);
sub _build_output {
    my ($self) = @_;
    return Rent::PIQT::Output::TSV->new(controller => $self);
}

# The cache, config, db, and output attributes need a reference back to the
# controller (that's us).
sub _set_controller {
    $_[1]->controller($_[0]);
}

# Registered internal commands.
has '_commands' => (is => 'rw', isa => 'HashRef', lazy_build => 1);
sub _build_commands {
    return {};
}

# Flag whether process is done or not.
has '_done' => (is => 'rw', isa => 'Bool', default => sub { 0 }, required => 1);

# The current prompt. The default ain't pretty.
has '_prompt' => (is => 'rw', isa => 'Str', lazy_build => 1);
sub _build_prompt {
    return '> ';
}

# Terminal handler, defaults to Term::ReadLine. The selection of a proper driver
# is done magically by Term::ReadLine.
has '_term'   => (is => 'ro', isa => 'Term::ReadLine', lazy_build => 1);
sub _build_term {
    my ($self) = @_;
    my $h = $self->config->history_file || $ENV{'HOME'} . '/.piqt_history';
    my $o = $self->output;

    my $t = Term::ReadLine->new('piqt');

    if ($t->ReadLine eq 'Term::ReadLine::Gnu') {
        $t->stifle_history($ENV{'HISTSIZE'} || 2000);
        $t->ReadHistory($h) if -f $h;
        $t->have_readline_history(1) if $t->can('have_readline_history');

        $o->info("Welcome to piqt " . $self->version . " with GNU readline support");
    } elsif ($t->ReadLine eq 'Term::ReadLine::Perl') {
        $t->Attribs->{'MaxHistorySize'} = 500;
        $t->have_readline_history(1) if $t->can('have_readline_history');

        $o->warn("piqt: Command line history will not survive multiple sessions.");
        $o->warn("      Install Term::ReadLine::Gnu to fix that.");
        $o->info("Welcome to piqt " . $self->version . " with Perl readline support");
    } else {
        $o->warn("piqt: Command line history will probably not survive multiple");
        $o->warn("      sessions. Install Term::ReadLine::Gnu to ensure it.");
        $o->info("Welcome to piqt " . $self->version . " with unknown readline support");
    }

    $t->Attribs->{'completion_function'} = sub { $self->db->name_completion(@_) };
}

sub process {

}

sub register {
    my ($self, @args) = @_;
    my $code = pop @args;
    foreach (@args) {
        $self->_commands->{$_} = $code;
    }
}

sub run {
    my ($self) = @_;
    my $query = '';

    $self->register('exit', 'quit', '\q', sub { $_[0]->_done(1) });
    $self->_prompt($self->db->connect_string);

    while (!$self->_done) {
        $query .= $self->_term->readline($self->_prompt);
        last unless defined $query;

        next if $query =~ /^\s*$/s;
        next if $self->execute($query);

        unless ($self->db->query_is_complete($query)) {
            $self->_prompt('> ');
            $query .= ' ';
            next;
        }

        $query =~ s#[;/]\s*$##g;
        #if ($self->config->echo) {
        #    $query =~ s#\s+# #g;
        #    $self->output->debug($query);
        #    $self->output->debug("{ROW LIMIT " . $self->config->limit . "}") if $self->config->limit;
        #}

        $self->db->execute($query);
        $self->_prompt($self->db->connect_string);
    }

    $self->cache->touch;

    do {
        my $t = $self->_term;
        if ($t->ReadLine eq 'Term::ReadLine::Gnu') {
            $t->WriteHistory($self->config->history_file);
        } elsif ($t->ReadLine eq 'Term::ReadLine::Perl') {
            if ($t->can('GetHistory')) {
                if (open HIST, '>', $self->config->history_file) {
                    my @lines = $t->GetHistory;
                    print HIST join("\n", @lines);
                    close HIST;
                }
            }
        }
    };

    $self->db->disconnect;
}

1;


package main;

use strict;
use Getopt::Long;
use Pod::Usage;

my $help = undef;
my $verbose = undef;

Getopt::Long::config('no_ignore_case');
GetOptions(
    'help|?'    => \$help,
    'verbose'   => \$verbose,
) or pod2usage(2);

STDOUT->autoflush(1);
STDERR->autoflush(1);

pod2usage(1) if $help;

my ($conn, $sql) = @ARGV;

my $repl = Rent::PIQT::REPL->new(
    cache  => Rent::PIQT::Cache::File->new(".piqt_cache"),
    config => Rent::PIQT::Config::File->new(".piqtrc"),
    db     => Rent::PIQT::DB::Oracle->new($conn),
);

if ($sql) {
    $repl->config->verbose(0) unless $verbose;
    $repl->output(Rent::PIQT::Output::CSV->new);
    $repl->process($sql);
} else {
    $repl->run;
}
