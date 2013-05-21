package Rent::PIQT::REPL;

use Moo;

use Class::Load qw/try_load_class/;
use Data::Dumper;
use Term::ReadLine;

our $VERSION = '0.02.0601';

# Generate the 'isa' clause for some 'has' below.
sub _generate_isa_for {
    my ($name) = @_;
    return sub {
        die "'" . lc($name) . "' attribute of Rent::PIQT::REPL is required" unless $_[0];
        my $info = ref($_[0]) || $_[0];
        die "'" . lc($name) . "' attribute of Rent::PIQT::REPL, which is a '$info' must implement Rent::PIQT::Component" unless $_[0]->does("Rent::PIQT::Component");
        die "'" . lc($name) . "' attribute of Rent::PIQT::REPL, which is a '$info' must implement Rent::PIQT::$name" unless $_[0]->does("Rent::PIQT::$name");
    };
}

# Returns a subroutine that will search for a class under C<$base>.
sub _search_and_instantiate_under {
    my ($base) = @_;
    return sub {
        my ($val) = @_;
        return unless $val;
        return $val if ref $val eq $base;

        my ($klass, @args) = ref $val eq 'ARRAY' ? @$val : ($val, );
        return unless $klass;

        $klass = _search_under($base, $klass);
        return $klass->new(@args);
    }
}

# Searches for a C<$klass> under C<$base>, or dies trying.
sub _search_under {
    my ($base, $klass) = @_;

    my @permutations = (
        $klass,
        ucfirst($klass),
        join('', map { ucfirst $_ } split(/(?<=[A-Za-z])_(?=[A-Za-z])|\b/, $klass)),
        uc($klass),
    );

    my ($success, $error);
    foreach my $klass_name (map { $base . '::' . $_ } @permutations) {
        ($success, $error) = try_load_class($klass_name);
        return $klass_name if $success;
    }

    require Carp;
    local $Carp::CarpLevel = $Carp::CarpLevel + 2;
    Carp::croak($error);
}

# Reference to cache handler. Required, defaults to memory cache.
has 'cache' => (
    is => 'rw',
    isa => _generate_isa_for('Cache'),
    required => 1,
    coerce => _search_and_instantiate_under('Rent::PIQT::Cache'),
    trigger => \&_set_controller,
);

# Configuration container. Required, defaults to empty config.
has 'config' => (
    is => 'rw',
    isa => _generate_isa_for('Config'),
    required => 1,
    coerce => _search_and_instantiate_under('Rent::PIQT::Config'),
    trigger => \&_set_controller,
);

# Database handler to support multiple database dialects. Required, but no
# default is provided.
has 'db' => (
    is => 'rw',
    isa => _generate_isa_for('DB'),
    required => 1,
    coerce => sub {
        my ($val) = @_;
        return unless $val;
        return $val if ref $val && $val->does('Rent::PIQT::DB');

        my ($klass, @args);
        if (ref $val eq 'ARRAY') {
            ($klass, @args) = @$val;
        } elsif ($val =~ m{([^:]+)://([^\?]+)(\?(.+))?}) {
            $klass = $1;

            my (%q);
            %q = map { split /=/ } split /&/, $4 if $4;
            $q{'database'} = $2;
            (@args) = (\%q);
        }
        return unless $klass;

        $klass = _search_under('Rent::PIQT::DB', $klass);
        return $klass->new(@args);
    },
    trigger => \&_set_controller,
);

# Output handler to support multiple output formats. Required, defaults to
# tab-delimited format.
has 'output' => (
    is => 'rw',
    isa => _generate_isa_for('Output'),
    required => 1,
    coerce => _search_and_instantiate_under('Rent::PIQT::Output'),
    trigger => \&_set_controller,
);

# The cache, config, db, and output attributes need a reference back to the
# controller (that's us).
sub _set_controller {
    $_[1]->controller($_[0]);
}

# Registered internal commands.
has '_commands' => (
    is => 'lazy',
    isa => sub { die "Commands must be a HashRef" unless ref $_[0] eq 'HASH' },
);
sub _build__commands {
    return {};
}

# Flag whether process is done or not.
has '_done' => (
    is => 'rw',
    isa => sub { die "Done flag must be Bool" if ref $_[0] },
    default => sub { 0 },
    required => 1,
);

# The current prompt. The default ain't pretty.
has '_prompt' => (
    is => 'rw',
    isa => sub { die "Prompt must be a String" if ref $_[0] },
    builder => 1,
);
sub _build__prompt {
    return '> ';
}

# Terminal handler, defaults to Term::ReadLine. The selection of a proper driver
# is done magically by Term::ReadLine.
has '_term'   => (
    is => 'lazy',
    isa => sub { die "Terminal must be a Term::ReadLine, not a " . ref($_[0]) unless ref $_[0] eq 'Term::ReadLine' },
);
sub _build__term {
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

    $self->config->history_file($h);

    $t->Attribs->{'completion_function'} = sub { $self->db->name_completion(@_) };
    return $t;
}

# Execute an internal command.
sub execute {
    my ($self, $command) = @_;
    return unless $self->_commands;

    $command = uc($command);

    if (exists $self->_commands->{$command}) {
        return $self->_commands->{$command}->($self);
    } else {
        my ($cmd_name, @cmd_args) = split /\s+/, $command;
        if (exists $self->_commands->{$cmd_name}) {
            return $self->_commands->{$cmd_name}->($self, @cmd_args);
        }
    }
}

# Process a line of SQL.
sub process {
}

# Register an internal command. Multiple commands can be registered at the same
# time by specifying multiple command names in the arguments. The last argument
# must be a code reference.
#
# The code reference should accept multiple arguments. The first argument is a
# reference to the REPL instance. The rest of the arguments are the pre-parsed
# command arguments as entered in the REPL interface.
sub register {
    my ($self, @args) = @_;
    my $code = pop @args;

    foreach (@args) {
        if (ref $code eq 'CODE') {
            $self->_commands->{uc($_)} = $code;
        } else {
            warn "Cannot register internal command '$_' to point to a " . ref($code);
        }
    }
}

sub run {
    my ($self) = @_;
    my $query = '';

    $self->_prompt($self->db->dsn . '> ');

    while (!$self->_done) {
        $self->output->out->print("\n");

        $query .= $self->_term->readline($self->_prompt);
        last unless defined $query;

        if ($query =~ /^\s*$/s || $self->execute($query)) {
            $query = '';
            next;
        }

        unless ($self->db->query_is_complete($query)) {
            $self->_prompt('> ');
            $query .= ' ';
            next;
        }

        $query = $self->db->sanitize($query);

        #$query =~ s#[;/]\s*$##g;
        #if ($self->config->echo) {
        #    $query =~ s#\s+# #g;
        #    $self->output->debug($query);
        #    $self->output->debug("{ROW LIMIT " . $self->config->limit . "}") if $self->config->limit;
        #}

        if ($self->db->prepare($query) && $self->db->execute) {
            if ($self->db->has_result_set) {
                $self->output->start($self->db->field_prototypes);
                while (my $row = $self->db->fetch_array) {
                    $self->output->record([ @$row ]);
                }

                $self->output->finish;
            } else {
            }
        } else {
            $self->output->error($self->db->last_error);
        }

        $self->_prompt($self->db->dsn . '> ');
        $query = '';
    }

    $self->cache->touch;

    if ($self->config->history_file) {
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
    }

    $self->db->disconnect;
}

# Return $VERSION
sub version {
    return $VERSION;
}

1;


package main;

use strict;
use Getopt::Long;
use IO::Handle;
use Pod::Usage;

use Rent::PIQT::Cache;
use Rent::PIQT::Config;
use Rent::PIQT::DB;
use Rent::PIQT::Output;

my $help = undef;
my $verbose = 0;

my $format      = 'csv';
my $output_file = undef;

Getopt::Long::config('no_ignore_case');
GetOptions(
    'help|?'    => \$help,
    'verbose+'  => \$verbose,

    'format'    => \$format,
    'output'    => \$output_file,
) or pod2usage(2);

STDOUT->autoflush(1);
STDERR->autoflush(1);

pod2usage(1) if $help;

my ($conn, $sql) = @ARGV;

my ($output_fh, $error_fh);
do {
    $error_fh = IO::Handle->new();
    $error_fh->fdopen(fileno(STDERR), 'w');
    $error_fh->autoflush(1);

    if ($output_file) {
        $output_fh = IO::File->new($output_file, 'w');
        $output_fh->autoflush(1);
    } else {
        $output_fh = IO::Handle->new();
        $output_fh->fdopen(fileno(STDOUT), 'w');
        $output_fh->autoflush(1);
    }
};

my $repl = Rent::PIQT::REPL->new(
    cache  => ["file", ".piqt_cache"],
    config => ["file", ".piqtrc"],
    db     => $conn || 'oracle://vqa',
    output => ["tabular", out => $output_fh, err => $error_fh],
);

$repl->register('exit', 'quit', '\q',
    sub {
        my ($self) = @_;
        $self->output->info("BYE");
        $self->_done(1);
        return 1;
    }
);
$repl->register('set',
    sub {
        my ($self, $name, $value) = @_;
        if (defined $value) {
            $self->output->info("SET $name $value");
        } else {
            $self->output->info("SET $name " . $self->config->$name);
        }

        return 1;
    }
);

if ($sql) {
    $repl->config->verbose($verbose || 0);
    $repl->output("csv");
    $repl->process($sql);
} else {
    $repl->config->verbose($verbose + 2);
    $repl->run;
}

exit();
