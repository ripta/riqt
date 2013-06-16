package Rent::PIQT::REPL;

use Moo;

use Carp;
use Class::Load qw/try_load_class/;
use Data::Dumper;
use Rent::PIQT::Util;
use String::Escape qw/quote printable/;
use Term::ReadLine;
use Time::HiRes qw/gettimeofday tv_interval/;

our $VERSION = '0.5.4';

# Generate the 'isa' clause for some 'has' below.
sub _generate_isa_for {
    my ($name) = @_;
    return sub {
        die "The '" . lc($name) . "' attribute of Rent::PIQT::REPL is required" unless $_[0];
        my $info = ref($_[0]) || $_[0];
        die "The '" . lc($name) . "' attribute of Rent::PIQT::REPL, which is a '$info' must implement Rent::PIQT::$name" unless $_[0]->does("Rent::PIQT::$name") || $_[0]->isa("Rent::PIQT::$name");
    };
}

# Returns a subroutine that will search for a class under C<$base>.
sub _search_and_instantiate_under {
    my ($base) = @_;
    return sub {
        my ($val) = @_;
        return unless $val;
        return $val if ref $val eq $base;
        return $val if ref($val) =~ /^\Q$base\E/;
        return $val if ref $val && ref $val ne 'ARRAY';

        my ($klass, @args) = ref $val eq 'ARRAY' ? @$val : ($val, );
        return unless $klass;

        $klass = _search_under($base, $klass);
        return $klass->new(@args);
    }
}

# Searches for a C<$klass> under C<$base>, or dies trying.
sub _search_under {
    my ($base, $klass) = @_;

    # If the $klass is provided as KLASS_name, try different permutations
    my %seen = ();
    my @permutations = grep {
        $seen{$_}++ == 0
    } map {
        $base . '::' . $_
    } (
        # as-is:
        $klass,
        # uppercased first, but don't normalize
        ucfirst($klass),
        # camelcase, but don't normalize
        join('', map { ucfirst $_ } split(/(?<=[A-Za-z])_(?=[A-Za-z])|\b/, $klass)),
        # uppercase everything
        uc($klass),
        # lowercase everything
        lc($klass),
        # uppercase first, with normalization
        ucfirst(lc($klass)),
        # camelcase, with normalization
        join('', map { ucfirst lc $_ } split(/(?<=[A-Za-z])_(?=[A-Za-z])|\b/, $klass)),
    );

    my ($success, $error);
    local $Carp::CarpLevel = $Carp::CarpLevel + 2;
    foreach my $klass_name (@permutations) {
        my $klass_file = $klass_name;
        $klass_file =~ s#::#/#g;

        ($success, $error) = try_load_class($klass_name);
        # print $success ? "OK: $klass_name\n" : "ERROR: $error\n";
        return $klass_name if $success;
        Carp::croak($error) if $error && $error !~ m/^Can't locate $klass_file/;
    }

    Carp::croak("Cannot find '" . $klass . "' under '" . $base . "'; tried: " . join(', ', @permutations));
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
        return $val if ref $val && UNIVERSAL::isa($val, 'Rent::PIQT::DB');

        my ($klass, @args);
        if (ref $val eq 'ARRAY') {
            ($klass, @args) = @$val;
            @args = { @args } if scalar(@args) % 2 == 0;
        } elsif ($val =~ m{^([^:]+)://([^\?]+)(\?(.+))?$}) {
            $klass = $1;

            my (%q);
            %q = map { split /=/ } split /&/, $4 if $4;
            $q{'database'} = $2;
            (@args) = (\%q);
        } else {
            die "unknown database connection string '$val'";
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
    $attr->POSTBUILD if $self->{'is_ready'} && $attr->can('POSTBUILD');
    return $attr;
}

# The verbosity level
has 'verbose' => (
    is => 'rw',
    required => 0,
    default => 0,
);

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
        $o->info;
    } elsif ($t->ReadLine eq 'Term::ReadLine::Perl') {
        $t->Attribs->{'MaxHistorySize'} = 500;
        $t->have_readline_history(1) if $t->can('have_readline_history');

        $o->warn("piqt: Command line history will not survive multiple sessions.");
        $o->warn("      Install Term::ReadLine::Gnu to fix that.");
        $o->info("Welcome to piqt " . $self->version . " with Perl readline support");
        $o->info;
    } else {
        $o->warn("piqt: Command line history will probably not survive multiple");
        $o->warn("      sessions. Install Term::ReadLine::Gnu to ensure it.");
        $o->info("Welcome to piqt " . $self->version . " with unknown readline support");
        $o->info;
    }

    # Set back the history file
    $self->config->history_file($h);

    # Attach a completion handler
    $t->Attribs->{'completion_function'} = sub { $self->db->name_completion(@_) };

    return $t;
}

sub _verify_buffer {
    my ($self, $buffer) = @_;
    return unless $buffer;

    $self->output->warnf("The query buffer contains a query that hasn't been executed:\n%s",
        indent_lines($buffer),
    );
    $self->output->warnf("Possibly the query wasn't properly ended?");
}

# Execute POSTBUILD on every component. These methods should be run after
# the controller is fully initialized, and after all triggers have run,
# which is why it's placed here.
sub BUILD {
    my ($self) = @_;
    $self->{'plugins'} ||= {};
    $self->{'start'} = [ gettimeofday ];

    # Run each component's POSTBUILD method
    foreach my $name (qw/cache config db output/) {
        my $attr = $self->$name;
        if ($attr->can('POSTBUILD')) {
            $self->output->debugf("Running POSTBUILD on %s", $attr);
            $attr->POSTBUILD;
        }
    }

    # Register verbosity setting after component POSTBUILDs, so that we can
    # override things if any component drivers override it, e.g., the config
    # driver can load a different verbose setting, which we don't want sticking
    $self->config->verbose($self->verbose);
    $self->config->register('verbose',
        only => 'i',
        hook => sub {
            my ($config, $name, $old_value, $new_value) = @_;
            $config->controller->verbose(int($new_value));
        },
        persist => 0,
    );

    $self->register('help', {
        signature => ['%s', '%s <command>'],
        help => q{
            This is the meta help for the help command.

            Specify a <command> to see the help documentation for that command. Some basic
            commands to get you started off:

                SET                 Set a configuration variable to a new value
                SHOW                Show a list of all configuration variables
                SHOW COMMANDS       Show a list of all commands
                QUIT                Quit PIQT

            If <command> contains whitespace, it should be single-quoted, for example,
            these two commands work the same:

                HELP SHOW
                HELP 'SHOW'

            but this command should be quoted, because SHOW COMMANDS contains a space:

                HELP 'SHOW COMMANDS'
        },
        code => sub {
            my ($ctrl, $args) = @_;
            my $o = $ctrl->output;

            $args ||= "help";
            $args = uc $args;
            $args =~ s/^\s+|\s+$//g;
            unless (exists $ctrl->_commands->{$args}) {
                $o->errorf("Unknown command %s. Type 'SHOW COMMANDS' for full list.",
                    quote($args),
                );
                return 1;
            }

            my $cmd_info = $ctrl->_commands->{$args};

            $o->info;
            $o->info($o->colorize("NAME", "bold white"));
            $o->info($o->reindent($args, 1));

            $o->info;
            $o->info($o->colorize("SYNOPSIS", "bold white"));
            if (ref $cmd_info->{'signature'} eq 'ARRAY') {
                foreach (@{ $cmd_info->{'signature'} }) {
                    $o->infof($o->reindent($_, 1), $args);
                }
            } else {
                $o->infof($o->reindent($cmd_info->{'signature'}, 1), $args);
            }

            if (defined $cmd_info->{'help'}) {
                $o->info;
                $o->info($o->colorize("DESCRIPTION", "bold white"));
                $o->info($o->reindent($cmd_info->{'help'}, 1));
            }

            return 1;
        },
    });

    $self->register('show commands', {
        help => q{
            List all available commands and which package provides each of them. In verbose
            level 2 and above, also list when each command was registered.
        },
        code => sub {
            my ($ctrl, $args) = @_;
            my $o = $ctrl->output;

            die "Syntax error: SHOW COMMANDS does not take any arguments" if $args;

            $o->start(
                [
                    {name => "Command",         type => "str", length => 255},
                    $self->verbose >= 2 ? {name => "Signature",       type => "str", length => 1024} : (),
                    $self->verbose >= 2 ? {name => "Registered At",   type => "int", length => 20} : (),
                    $self->verbose >= 2 ? {name => "Registered In",   type => "str", length => 255} : (),
                    {name => "Registered By",   type => "str", length => 255},
                ]
            );

            foreach my $cmd (sort $self->internal_commands) {
                my $opts = $self->_commands->{$cmd};
                $o->record([
                    $cmd,
                    $self->verbose >= 2 ? sprintf($opts->{'signature'}, $cmd) : (),
                    $self->verbose >= 2 ? $opts->{'created_at'} * 1000 : (),
                    $self->verbose >= 2 ? $opts->{'caller_file'} . ':' . $opts->{'caller_line'} : (),
                    $opts->{'caller_package'},
                ]);
            }

            $o->finish;
            return 1;
        },
    });

    # Register "load plugin" command now that logging and components are
    # all set up and ready
    $self->register('load plugin', {
        signature => '%s <package_name>',
        help => q{
            Loads a plugin package into the current session. The <package_name> must be
            quoted. If the package name contains ::, or begins with ::, it is used as-is.
            Otherwise, the package name is searched under the PIQT::Plugins namespace.
        },
        code => sub {
            my ($ctrl, $args) = @_;
            my $name = unquote_or_die($args);

            if ($ctrl->load_plugin($name)) {
                $ctrl->output->okf("Plugin %s loaded successfully", quote($name));
            }

            return 1;
        },
    });

    # Register "show plugin" command
    $self->register('show plugin', 'show plugins', {
        help => q{
            List all plugins that are currently loaded.
        },
        code => sub {
            my ($ctrl, $args) = @_;
            my $o = $ctrl->output;

            die "Syntax error: SHOW PLUGINS does not take any arguments" if $args;

            $o->start(
                [
                    {name => "Name",        type => "str", length => 255},
                    {name => "Class",       type => "str", length => 255},
                    {name => "Instance",    type => "str", length => 255},
                    {name => "Created At",  type => "int", length => 20},
                ]
            );

            foreach my $klass (sort keys %{$self->{'plugins'}}) {
                my $name = $klass;
                $name =~ s/.*:://;

                my $instance = $self->{'plugins'}->{$klass}->{'instance'};
                $instance =~ s/.*=//;

                my $created_at = $self->{'plugins'}->{$klass}->{'created_at'};

                $o->record([$name, $klass, $instance, $created_at * 1000]);
            }

            $o->finish;
            return 1;
        },
    });

    # Register > command to forward the result set
    $self->register('>', {
        signature => [
            '%s',
            '%s <limit>',
        ],
        help => q{
            Retrieve the next result set produced by the last query.

            An existing query must be active, and already have been executed. Queries in
            the buffer are not automatically executed. This command does not modify or
            munge the contents of the buffer.

            An optional, numeric <limit> may also be specified. If no limit is specified
            explicitly, the value of the LIMIT and DEFLIMIT configuration variables are
            used, in that order of precedence.

            Specify a <limit> of -1 to turn off all limits, and ignore the LIMIT and
            DEFLIMIT configuration variables.

            This command can be specified as many times, one after another, in order to
            continue to the next result set.
        },
        code => sub {
            my ($self, $args) = @_;
            my $limit = $args
                ? int($args)
                : $self->config->limit
                    || $self->config->deflimit
                    || 0;

            # Check for an active query
            unless ($self->db->statement) {
                $self->output->error("No active query.");
                return 1;
            }

            # Ensure that the query has a result set first
            unless ($self->db->has_result_set) {
                $self->output->error("Active query has no result set.");
                return 1;
            }

            $self->output->start_timing;
            $self->output->infof("Query: %s", $self->db->last_query) if $self->db->last_query && $self->config->echo;

            # Only show a result set if the query produces a result set
            my $row_num = $self->db->display($self->output, $limit);
            $self->output->finish_timing($row_num || $self->db->rows_affected);
            return 1;
        },
    });

    # Register an extra exit command; the \q alias is from mysql-cli
    $self->register('exit', 'quit', '\q', {
        help => q{
            Exit the interactive interface.
        },
        code => sub {
            my ($self) = @_;
            $self->output->debugf("REPL age is %s", $self->tick);
            $self->output->info("BYE");
            $self->_done(1);
            return 1;
        },
    });

    $self->{'is_ready'} = 1;
}

# Execute an internal command.
sub execute {
    my ($self, $command) = @_;
    $command =~ s/;$//;
    $command =~ s/^\s+|\s+$//g;
    return unless $self->_commands;

    my @commands = sort { length($b) <=> length($a) || $a cmp $b } keys %{ $self->_commands };
    my @matches = grep { $command =~ /^\Q$_\E(?:\b|\s+\S+.*|)$/i } @commands;

    if (scalar(@matches)) {
        $self->output->debugf("Execute internal command:");
        $self->output->debugf("    Sort-cand: %s", join(", ", @commands));
        $self->output->debugf("    Matches  : %s", join(", ", @matches));

        my $command_name = $matches[0];
        my $args = $command;
        $args =~ s/^\Q$command_name\E//i;
        $args =~ s/^\s+//;

        $self->output->debugf("    Execute  : %s(%s)", $command_name, $args ? quote(printable($args)) : '');
        return $self->_commands->{$command_name}->{'code'}->($self, $args);
    }

    return 0;
}

sub internal_commands {
    my ($self) = @_;
    return () unless $self->_commands;
    return sort keys %{ $self->_commands };
}

# Load a plugin and install it dynamically.
sub load_plugin {
    my ($self, $plugin_name) = @_;
    my $plugin = undef;

    if ($plugin_name =~ /::/) {
        $plugin_name =~ s/^:://;
        $plugin = eval {
            my ($load_success, $load_error) = try_load_class($plugin_name);
            die $load_error unless $load_success;
            $plugin_name;
        };
    } else {
        $plugin = eval { _search_under('Rent::PIQT::Plugin', $plugin_name) };
    }

    if ($plugin) {
        if (exists $self->{'plugins'}->{$plugin}) {
            $self->output->warnf("Plugin %s has already been loaded",
                quote($plugin_name),
            );
            return 0;
        }

        $self->output->debugf("Loaded plugin %s", quote($plugin));
        my $instance = eval { $plugin->new(controller => $self) };
        if ($@) {
            $self->output->errorf("Cannot instantiate plugin '%s':\n\t%s",
                $plugin_name,
                $@ || 'unknown error in ' . __PACKAGE__ . ' line ' . __LINE__,
            );
            return 0;
        }

        $self->{'plugins'}->{$plugin} = {
            instance    => $instance,
            created_at  => $self->tick,
            request_name=> $plugin_name,
        };

        return 1;
    } else {
        $self->output->errorf("Cannot load plugin '%s':\n\t%s",
            $plugin_name,
            $@ || 'unknown error in ' . __PACKAGE__ . ' line ' . __LINE__,
        );
        return 0;
    }
}

# Process a line of SQL, command, or block. Returns:
#  0 if the query couldn't be processed because it was incomplete;
# +1 if the query was successful;
# +2 if the query was an internal command;
# +4 if the query was an SQL query.
sub process {
    my ($self, $buffer, $line) = @_;

    # If the last line is '/', then re-execute the buffer, which means
    # we need to skip appending to the query and checking for internal
    # command execution; anything that starts with @ is a file
    if ($$buffer eq '' && $line =~ /^@@?\s*(\S+)/) {
        $self->output->debugf("Executing %s, if available", quote($1));
        $self->run_file($1);
        return 3;
    } elsif ($line eq '/') {
        if ($self->db->last_query) {
            $$buffer = "" . $self->db->last_query;
        } else {
            $self->output->error('Execution buffer is empty. Please specify a query or PL/SQL block to execute.');
            return 2;
        }
    } else {
        $self->output->debugf("Read: %s", quote(printable($line)));
        $$buffer .= $line;

        # Skip any blank lines
        if ($$buffer =~ /^\s*$/s) {
            $$buffer = '';
            return 1;
        }

        # Skip any internal commands correctly handled
        if (eval { $self->execute($$buffer) }) {
            $$buffer = '';
            return 3;
        }
        if ($@) {
            $$buffer = '';
            die $@;
        }

        # Display a continuation prompt if the query isn't already complete
        unless ($self->db->query_is_complete($$buffer)) {
            $$buffer .= "\n";
            return 0;
        }
    }

    # Sanitize the query as necesary
    $$buffer = $self->db->sanitize($$buffer);

    # Prepare and execute the query
    $self->output->start_timing;
    if ($self->db->prepare($$buffer, save_query => 1) && $self->db->execute) {
        $self->output->infof("Query: %s", $$buffer) if $$buffer && $self->config->echo;

        # Only show a result set if the query produces a result set
        my $row_num = 0;
        if ($self->db->has_result_set) {
            my $limit = $self->config->limit || $self->config->deflimit || 0;
            $row_num = $self->db->display($self->output, $limit);
        }

        $self->output->finish_timing($row_num || $self->db->rows_affected);

        $$buffer = '';
        return 5;
    } else {
        $self->output->reset_timing;
        $self->output->error($self->db->last_error);

        $$buffer = '';
        return 4;
    }
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
    my ($c_pkg, $c_file, $c_line) = caller;

    my ($code, $opts);
    do {
        my $code_or_opts = pop @args;
        if (ref $code_or_opts eq 'CODE') {
            $code = $code_or_opts;
            $opts = {
                signature => '%s',
            };
        } elsif (ref $code_or_opts eq 'HASH') {
            $opts = $code_or_opts;
            $code = delete $opts->{'code'};
        }
    };

    die "Cannot register internal command %s, because no subroutine was given" unless $code;
    die "Cannot register internal command %s, because the given code is not a subroutine" unless ref $code eq 'CODE';

    foreach (@args) {
        $self->output->debugf("Registering internal command %s => %s", quote($_), $code);
        $self->_commands->{uc($_)} = {
            code            => $code,
            caller_package  => $c_pkg,
            caller_file     => $c_file,
            caller_line     => $c_line,
            created_at      => $self->tick,
            signature       => $opts->{'signature'} || '%s',
            help            => $opts->{'help'} || undef,
        };
    }
}

# The main loop of the REPL, which handles all four stages, with the option
# to run a single query, if provided.
sub run {
    my ($self, $query) = @_;

    # If a query was provided, process it and return immediately
    if ($query) {
        $self->run_query($query);
        return;
    }

    $self->run_repl;
}

# Run queries from a single file. Files can load other files.
sub run_file {
    my ($self, $file) = @_;
    unless ($file) {
        $self->output->error("Filename is required.");
        return;
    }

    $self->output->debugf("Loading SQL %s", quote($file));

    $file =~ s#^~/#$ENV{'HOME'} . '/'#e;
    $file =~ s/;$//;
    unless (-e $file) {
        $self->output->errorf("Cannot load file %s: file does not exist", quote($file));
        $self->output->println;
        return 0;
    }

    open my $fh, $file or do {
        $self->output->errorf("Cannot open file %s: %s", quote($file), $!);
        $self->output->println;
        return 0;
    };

    # Loop until the end of the file
    my $buffer = '';
    my $lineno = 0;
    while (++$lineno) {
        # Read a single line from the terminal
        my $line = <$fh>;
        last unless defined $line;
        chomp $line;

        eval { $self->process(\$buffer, $line) };
        if ($@) {
            $self->output->errorf("Process died at %s line %d", $file, $lineno);
            $self->output->errorf("    %s", $self->sanitize_death($@));
            $self->output->println;
            close $fh;
            return;
        }

        $self->output->println;
    }

    $self->_verify_buffer($buffer);

    close $fh;
    $self->output->debugf("Successfully processed %d lines from %s", $lineno, quote($file));
    return;
}

# Run a single line of query.
sub run_query {
    my ($self, $query) = @_;
    $query .= ';' unless $query =~ /;\s*$/;

    my @lines = split /\r?\n/, $query;
    $self->output->debugf("Running single query (%d lines)", scalar(@lines));

    my $buffer = '';
    my $lineno = 0;
    while (my $line = shift @lines) {
        $lineno++;
        eval { $self->process(\$buffer, $line) };
        if ($@) {
            $self->output->errorf("Error at <STDIN> line %d:\n\t%s", $lineno, $self->sanitize_death($@));
            return 0;
        }
    }

    $self->_verify_buffer($buffer);

    return 1;
}

# Start an interactive session on the current database driver.
sub run_repl {
    my ($self) = @_;
    my $lineno = 0;

    # Set the default prompt to the database's data source name
    $self->output->debugf("Entering interactive mode for resource %s", quote($self->db->auth_info));
    $self->_prompt($self->db->auth_info . '> ');

    # Loop until we're told to exit
    my $buffer = '';
    while (!$self->_done) {
        $lineno++;

        # Read a single line from the terminal
        my $line = $self->_term->readline($self->_prompt);
        last unless defined $line;

        if (eval { $self->process(\$buffer, $line) }) {
            $self->_prompt($self->db->auth_info . '> ');
            $self->output->println;
        } elsif ($@) {
            $self->output->errorf("Error at <INTERACTIVE> line %d:\n\t%s", $lineno, $self->sanitize_death($@));
            $self->output->println;
        } else {
            $self->_prompt('+> ');
        }
    }

    $self->_verify_buffer($buffer);

    # Touch the cache (?)
    # TODO: remove this and make it less error-prone in the future
    $self->cache->touch;
    $self->cache->save;

    # Save back the config file
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
}

# Sanitize die/warn() messages caught by eval{}. In debug mode, the string
# is left as-is. Otherwise, any filenames and line numbers in the string is
# parsed out; even nested ones.
sub sanitize_death {
    my ($self, $str) = @_;
    return $str if $self->verbose >= 2;

    $str =~ s/ at \S+ line \d+\.?\s*//g;
    return $str;
}

# Timing tick in milliseconds since start of object.
sub tick {
    my ($self) = @_;
    return tv_interval($self->{'start'}) * 1000;
}

# Return $VERSION
sub version {
    return $VERSION;
}

sub with_output {
    my ($self, $temporary, $work) = @_;
    return unless $temporary;
    return unless $work;
    return unless ref $work eq 'CODE';

    my $current = $self->output;
    $self->output([$temporary, $current]);

    my $retval = $work->($self->output);
    $self->output($current);

    return $retval;
}

1;
