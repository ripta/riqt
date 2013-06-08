package Rent::PIQT::Plugin::Print;

use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('print',
        sub {
            my ($ctrl, $args) = @_;
            $ctrl->output->println(parse_argument_string($args));
            return 1;
        },
    );
}

1;
