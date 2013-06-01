package Rent::PIQT::REPL;

use Moo;

use Carp;
use Class::Load qw/try_load_class/;
use Data::Dumper;
use Term::ReadLine;

our $VERSION = '0.5.0';

# Generate the 'isa' clause for some 'has' below.
sub _generate_isa_for {
    my ($name) = @_;
    return sub {
        die "'" . lc($name) . "' attribute of Rent::PIQT::REPL is required" unless $_[0];
        my $info = ref($_[0]) || $_[0];
        die "'" . lc($name) . "' attribute of Rent::PIQT::REPL, which is a '$info' must implement Rent::PIQT::$name" unless $_[0]->does("Rent::PIQT::$name") || $_[0]->isa("Rent::PIQT::$name");
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

    my %seen = ();
    my @permutations = grep {
        $seen{$_}++ == 0
    } map {
        $base . '::' . $_
    } (
        $klass,
        ucfirst($klass),
        join('', map { ucfirst $_ } split(/(?<=[A-Za-z])_(?=[A-Za-z])|\b/, $klass)),
        uc($klass),
    );

    my ($success, $error);
    local $Carp::CarpLevel = $Carp::CarpLevel + 2;
    foreach my $klass_name (@permutations) {
        ($success, $error) = try_load_class($klass_name);
        return $klass_name if $success;
        Carp::croak($error) if $error && $error !~ m/^Can't locate/;
    }

    Carp::croak("Cannot locate any of " . join(', ', @permutations));
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
        } elsif ($val =~ m{^([^:]+)://([^\?]+)(\?(.+))?$}) {
            $klass = $1;

            my (%q);
            %q = map { split /=/ } split /&/, $4 if $4;
            $q{'database'} = $2;
            (@args) = (\%q);
        } elsif ($val =~ m{^([^/]+)/([^@]+)@(.+)$}) {
            $klass = 'oracle';
            push @args, {
                username => $1,
                password => $2,
                database => $3,
            };
        } else {
            die "unknown database format '$val'";
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
    my ($self, $attr) = @_;
    $attr->controller($self);
    return $attr;
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
    required => 0,
);

# The current prompt. The default ain't pretty.
has '_prompt' => (
    is => 'rw',
    isa => sub { die "Prompt must be a String" if ref $_[0] },
    builder => 1,
);
sub _build__prompt {
    return 'SQL> ';
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

    # Depending on the ReadLine driver---and unfortunately we have to compare
    # by string---we have to set up history differently
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

    # Set back the history file
    $self->config->history_file($h);

    # Attach a completion handler
    $t->Attribs->{'completion_function'} = sub { $self->db->name_completion(@_) };

    return $t;
}

# Execute POSTBUILD on every component.
sub BUILD {
    my ($self) = @_;
    foreach my $name (qw/cache config db output/) {
        my $attr = $self->$name;
        $attr->POSTBUILD if $attr->can('POSTBUILD');
    }
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
            $self->output->warnf("Cannot register internal command '%s' to point to a %s", $_, ref($code));
        }
    }
}

# The main loop of the REPL, which handles all four stages.
sub run {
    my ($self) = @_;
    my $query = '';

    # Set the default prompt to the database's data source name
    $self->_prompt($self->db->dsn . '> ');

    # Loop until we're told to exit
    while (!$self->_done) {
        # Read a single line from the terminal
        $query ||= '';
        $query .= $self->_term->readline($self->_prompt);
        last unless defined $query;

        # Skip any blank lines and any internal commands correctly handled
        if ($query =~ /^\s*$/s || $self->execute($query)) {
            $self->output->println;
            $query = '';
            next;
        }

        # Display a continuation prompt if the query isn't already complete
        unless ($self->db->query_is_complete($query)) {
            $self->_prompt('> ');
            $query .= ' ';
            next;
        }

        # Sanitize the query as necesary
        $query = $self->db->sanitize($query);

        # Prepare and execute the query
        if ($self->db->prepare($query) && $self->db->execute) {
            # Only show a result set if the query produces a result set
            if ($self->db->has_result_set) {
                my $limit   = $self->config->limit || $self->config->deflimit || 0;
                my $row_num = 0;

                # Output a header and each record
                $self->output->start($self->db->field_prototypes);
                while (my $row = $self->db->fetch_array) {
                    $self->output->record([ @$row ]);
                    last if $limit && ++$row_num >= $limit;
                }

                # Finish up
                $self->output->finish;
                $self->output->info("There may be more rows") if $row_num >= $limit;
            } else {
                # TODO
            }
        } else {
            $self->output->error($self->db->last_error);
        }

        $self->output->println;
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
