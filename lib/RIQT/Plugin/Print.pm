package Rent::PIQT::Plugin::Print;

use Moo;

our $VERSION = '0.5.0';

with 'Rent::PIQT::Plugin';

our $TOKENS = {
    'date'      => sub {
        return scalar localtime();
    },
};

sub BUILD {
    my ($self) = @_;

    $self->controller->register('print', {
        code => sub {
            my ($ctrl, @args) = @_;
            my $line = "";
            foreach (@args) {
                if (is_quoted($_)) {
                    $line .= unquote($_);
                } else {
                    my ($token, $inner) = ($_ =~ /([^\(]+)(?:\((.*)\))?/);
                    if ($token) {
                        if (exists $TOKENS->{$token}) {
                            $line .= $TOKENS->{$token}->($inner);
                        } else {
                            die "Evaluation error: unknown token '$token'";
                        }
                    } else {
                        die "Parse error: $_\n             ^";
                    }
                }
            }
            $ctrl->output->println($line);
            return 1;
        },
    });
}

1;
