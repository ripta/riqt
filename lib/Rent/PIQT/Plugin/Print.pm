package Rent::PIQT::Plugin::Print;

use Moo;

our $VERSION = '0.5.0';

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('print', {
        slurp => 1,
        code => sub {
            my ($ctrl, $args) = @_;
            $ctrl->output->println(unquote_or_die($args));
            return 1;
        },
    });
}

1;
