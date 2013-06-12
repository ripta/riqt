package Rent::PIQT::Plugin::TerseQuery;

use List::Util qw/max/;
use Moo;
use Rent::PIQT::Util;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('`', {
        signature => "%s (relation_set) [conditions] {projections}",
        help => qq{
        },
        code => sub {
            my ($ctrl, $args) = @_;
            my $o = $ctrl->output;

            $o->info('TERSE (EXPANSION=1)');

            return 1;
        },
    });
}

1;
