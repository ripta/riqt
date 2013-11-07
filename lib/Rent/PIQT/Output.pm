package Rent::PIQT::Output;

use Data::Dumper;
use Moo::Role;
use Term::ANSIColor;
use Time::HiRes qw/gettimeofday tv_interval/;

with 'Rent::PIQT::Component';

has 'err' => (
    is => 'ro',
    isa => sub { die "Attribute 'err' of 'Rent::PIQT::Output' must be an IO::Handle" unless $_[0]->isa('IO::Handle') },
    required => 1,
);
has 'out' => (
    is => 'ro',
    isa => sub { die "Attribute 'out' of 'Rent::PIQT::Output' must be an IO::Handle" unless $_[0]->isa('IO::Handle') },
    required => 1,
);

has 'is_interactive' => (
    is => 'lazy',
    required => 0,
);
sub _build_is_interactive {
    return -t $_[0]->err;
}

has 'start_time', (is => 'rw');

has 'character_set', (is => 'rw');
has 'unicode', (is => 'rw');

# The start and end of output. Signatures:
#   start(\@fields)
#       [{name => ..., type => ..., length => ...}, ...]
#       where type in (str, int, float, bitflag, bool, date)
#   finish()
requires qw/start finish/;

# A single record:
#   record(\@field_values)
requires qw/record/;

sub BUILDARGS {
    my ($class, $proto) = @_;

    # Validate the arguments
    die 'Invalid prototype for ' . __PACKAGE__ . '->BUILDARGS: a HASHREF or hash-convertible object is required' unless $proto;
    die 'Invalid prototype for ' . __PACKAGE__ . '->BUILDARGS: ' . $proto . ' is not a HASHREF or hash-convertible object' unless ref $proto;

    # Attempt to copy the prototype from an object that knows of err and out
    if (ref $proto ne 'HASH') {
        if (ref $proto && $proto->can('err') && $proto->can('out')) {
            $proto = {
                err             => $proto->err,
                out             => $proto->out,
                character_set   => $proto->character_set,
                unicode         => $proto->unicode,
            };
        }
    }

    # Validate the prototype
    die 'Invalid prototype for ' . __PACKAGE__ . '->BUILDARGS: ' . $proto . ' is not a HASHREF or a hash-convertible object' unless ref $proto eq 'HASH';
    die 'Incomplete prototype for ' . __PACKAGE__ . ': missing "err" value' unless defined $proto->{'err'};
    die 'Incomplete prototype for ' . __PACKAGE__ . ': missing "out" value' unless defined $proto->{'out'};

    return $proto;
}

sub POSTBUILD {
    my ($self) = @_;

    $self->controller->output->debugf("Output driver %s is ready: OUT=(%s) ERR=(%s)",
        ref $self,
        $self->out ? $self->out->fileno : '',
        $self->err ? $self->err->fileno : '',
    );

    # Unregister any existing mode hooks, and register a new one; without
    # unregistering first, the mode hook would run in a loop
    $self->controller->config->unregister('mode');
    $self->controller->config->register('mode',
        only => 'i',
        hook => sub {
            my ($config, $name, $old_value, $new_value) = @_;
            my $o = $config->controller->output;

            $o->debugf("MODE HOOK FOR %s, current active output driver is %s; name=%s old=%s new=%s\n",
                quote($self) // 'undef',
                quote($config->controller->output) // 'undef',
                $name // 'undef',
                $old_value // 'undef',
                $new_value // 'undef',
            );

            $config->controller->output([
                $new_value,
                $config->controller->output,
            ]);
        },
    );

    # Character sets and unicode support for unicode-aware output drivers
    do {
        $self->controller->config->register('character_set',
            persist => 0,
            hook => sub {
                my ($config, $name, $old_value, $new_value) = @_;
                $self->controller->output->character_set($new_value);
                return $config->unicode($new_value && $new_value =~ /UTF|UCS/i ? 1 : 0);
            },
        );

        $self->controller->config->register('unicode',
            persist => 0,
            hook => sub {
                my ($config, $name, $old_value, $new_value) = @_;
                $self->debugf("Output driver %s set UNICODE to %s", $self, $new_value ? 'ON' : 'OFF');
                $self->controller->output->unicode($new_value ? 1 : 0);
            },
        );

        if (exists $ENV{'LC_CTYPE'}) {
            $self->controller->config->character_set($ENV{'LC_CTYPE'});
        } elsif (exists $ENV{'LANG'}) {
            $self->controller->config->character_set($ENV{'LANG'});
        } else {
            $self->controller->config->character_set('ISO-8859-1');
        }
    };
}

sub colorize {
    my ($self, $msg, $color) = @_;
    $msg = '[' . sprintf("%12.3f", $self->controller->tick) . '] ' . $msg if $self->controller && $self->controller->verbose >= 3;

    return $msg unless $self->is_interactive;
    return $msg unless $self->controller->config->colors;

    return color($color) . $msg . color('reset');
}

sub data_set {
    my ($self, $field_definition, @records) = @_;
    if (ref $field_definition eq 'CODE') {
        ($field_definition, @records) = $field_definition->();
    }

    $self->start($field_definition);
    foreach (@records) {
        $self->record($_);
    }
    $self->finish;
}

sub debug {
    my ($self, $msg) = @_;
    return unless $self->controller->verbose;
    return unless $self->controller->verbose >= 2;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "cyan"));
}

sub debugf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->debug(sprintf($msg, @args));
}

sub debugfq {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->debugf($msg, map { quote printable $_ } @args);
}

sub dump {
    my ($self, @objects) = @_;
    foreach (@objects) {
        $self->info(Dumper($_));
    }
}

sub error {
    my ($self, $msg) = @_;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "red"));
}

sub errorf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->error(sprintf($msg, @args));
}

sub errorfq {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->errorf($msg, map { quote printable $_ } @args);
}

sub finish_timing {
    my ($self, $rows_affected) = @_;
    return unless $self->start_time;
    return unless $self->controller->verbose;
    return unless $self->controller->config->timing;

    # Calculate time passed
    my $duration = tv_interval($self->start_time);

    # Show different formatting depending on duration
    my $timing_string;
    if ($duration >= 100) {
        $timing_string = sprintf('%0d:%05.2f', int($duration / 60), $duration % 60);
    } else {
        $timing_string = sprintf('%0.3f s', $duration);
    }

    if (defined $rows_affected) {
        $self->okf("%d %s affected in %s",
            $rows_affected,
            $rows_affected == 1 ? 'row' : 'rows',
            $timing_string,
        );
    } else {
        $self->okf("Completed in %s",
            $timing_string,
        );
    }

    $self->reset_timing;
}

sub info {
    my ($self, $msg) = @_;
    return unless $self->controller->verbose;
    return unless $self->controller->verbose >= 1;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "white"));
}

sub infof {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->info(sprintf($msg, @args));
}

sub infofq {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->infof($msg, map { quote printable $_ } @args);
}

sub ok {
    my ($self, $msg) = @_;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "green"));
}

sub okf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->ok(sprintf($msg, @args));
}

sub okfq {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->okf($msg, map { quote printable $_ } @args);
}

sub print {
    my ($self, $msg) = @_;
    $msg ||= "";
    $self->out->print($msg);
}

sub printc {
    my ($self, $color, $msg) = @_;
    $color ||= "white";
    $msg ||= "";
    $self->print($self->colorize($msg, $color));
}

sub printf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->print(sprintf($msg, @args));
}

sub println {
    my ($self, $msg) = @_;
    $msg ||= "";
    $self->print("$msg\n");
}

sub printlnf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->println(sprintf($msg, @args));
}

sub reindent {
    my ($self, $msg, $amt) = @_;
    $msg ||= "";
    $amt ||= 1;
    return indent_lines(strip_spaces($msg), 1);
}

sub reset_timing {
    my ($self) = @_;
    $self->start_time(undef);
}

sub start_timing {
    my ($self) = @_;
    $self->start_time([ gettimeofday ]);
}

sub warn {
    my ($self, $msg) = @_;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "yellow"));
}

sub warnf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->warn(sprintf($msg, @args));
}

sub warnfq {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->warnf($msg, map { quote printable $_ } @args);
}

1;

=head1 NAME

Rent::PIQT::Output - Base class for PIQT output drivers

=head1 SYNOPSIS

This class should not be initialized directly, but rather, should be subclassed
with implementations of the methods: C<start>, C<finish>, C<record>, and
C<print>. See method documentation for more detail.

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
