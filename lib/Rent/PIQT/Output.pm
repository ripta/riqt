package Rent::PIQT::Output;

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
    return -t select;
}

has 'start_time', (is => 'rw');

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
    return unless $proto;
    return $proto if ref $proto eq 'HASH';
    return $proto unless $proto->can('err') && $proto->can('out');
    return {
        err => $proto->err,
        out => $proto->out,
    };
}

sub POSTBUILD {
    my ($self) = @_;
    $self->controller->config->register('mode',
        sub {
            my ($config, $name, $old_value, $new_value) = @_;
            $config->controller->output([
                $new_value,
                $config->controller->output,
            ]);
        },
    );
}

sub colorize {
    my ($self, $msg, $color) = @_;
    return $msg unless $self->is_interactive;

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
    return unless $self->controller->config->verbose;
    return unless $self->controller->config->verbose >= 2;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "cyan"));
}

sub debugf {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->debug(sprintf($msg, @args));
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

sub finish_timing {
    my ($self, $rows_affected) = @_;
    return unless $self->start_time;

    if (defined $rows_affected) {
        $self->infof("%d %s affected in %d ms",
            $rows_affected,
            $rows_affected == 1 ? 'row' : 'rows',
            int(tv_interval($self->start_time) * 1000),
        );
    } else {
        $self->infof("Completed in %d ms",
            int(tv_interval($self->start_time) * 1000),
        );
    }

    $self->reset_timing;
}

sub info {
    my ($self, $msg) = @_;
    return unless $self->controller->config->verbose;
    return unless $self->controller->config->verbose >= 1;

    $msg ||= "";
    $msg .= "\n";
    $self->err->print($self->colorize($msg, "white"));
}

sub infof {
    my ($self, $msg, @args) = @_;
    $msg ||= "";
    $self->info(sprintf($msg, @args));
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

sub print {
    my ($self, $msg) = @_;
    $msg ||= "";
    $self->out->print($msg);
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
    $self->info(sprintf($msg, @args));
}

1;
