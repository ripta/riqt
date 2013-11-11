package RIQT::Plugin::SqlPlusCompatibility;

use Moo;
use RIQT::Util;

our $VERSION = '0.5.0';

with 'RIQT::Plugin';

our $REGISTERED = {
    appinfo     => sub {
        my ($self, $value) = @_;
        return 0 unless $value;
        return 1 if uc $value eq 'ON';
        return 0 if uc $value eq 'OFF';
        return $value;
    },
    arraysize   => sub {
        my ($self, $value) = @_;
        return 15 unless $value;
        $value = 0 + $value;
        return 15 unless $value;
        return 15 if $value < 1;
        return $value;
    },
    autocommit  => sub {
        my ($self, $value) = @_;
        return 0 unless $value;
        return 0 if uc $value eq 'OFF';
        return 1 if uc $value eq 'ON';
        return 1 if uc $value =~ /^IMM/i;
        return 0 + $value;
    },
    autoprint   => sub {
        my ($self, $value) = @_;
        return 0 unless $value;
        return 1 if uc $value eq 'ON';
        return 0;
    },
    # autorecover => sub {
    # },
    # autotrace   => sub {
    # },
    blockterminator => sub {
        my ($self, $value) = @_;
        return '/' unless $value;
        return '/' if uc $value eq 'ON';
        return '/' if uc $value eq 'OFF';
        return substr($value, 0, 1);
    },
    cmdsep      => sub {
        my ($self, $value) = @_;
        return ';' unless $value;
        return ';' if uc $value eq 'ON';
        return ';' if uc $value eq 'OFF';
        return substr($value, 0, 1);
    },
    colsep      => sub {
        my ($self, $value) = @_;
        return $value || ' ';
    },
    compatibility   => sub {
        my ($self, $value) = @_;
        return 'NATIVE' unless $value;
        return $value if $value =~ /^(V5|V6|V7|V8)$/i;
        return 'NATIVE';
    },
    # concat
    # copycommit
    # copytypecheck
    # define
    # describe
    # echo
    # embedded
    # escape
    # feedback
    # flagger
    # flash
    # heading
    # headsep
    # instance
    # linesize
    # loboffset
    # logsource
    # long
    # longchunksize
    # markup
    # newpage
    null        => sub {
        my ($self, $value) = @_;
        return defined($value) ? $value : '(null)';
    },
    # numformat
    # numwidth
    # pagesize
    # pause
    # recsep
    # recsepchar
    # scan
    # serveroutput
    # showmode
    # space
    # sqlblanklines
    # sqlcase
    # sqlpluscompatibility
    # sqlcontinue
    # sqlnumber
    # sqlprefix
    # sqlprompt
    # sqlterminator
    # suffix
    # tab
    # termout
    time        => sub {
        my ($self, $value) = @_;
        return 0 unless $value;
        return 1 if uc $value eq 'ON';
        return 0;
    },
    timing      => sub {
        my ($self, $value) = @_;
        return 1 unless $value;
        return 0 if uc $value eq 'OFF';
        return 1;
    },
    # trimout
    # trimspool
    # underline
    # verify
    # wrap
};

sub BUILD {
    my ($self) = @_;

    $self->controller->register('spool',
        sub {
            my ($ctrl, $args) = @_;

            if ($args) {
                $args =~ s/^\s+//;
                $args =~ s/\s+$//;

                if ($args =~ /^OFF$/i) {
                    $ctrl->output->okf("Spooling is now OFF");
                } elsif ($args =~ /^OUT$/i) {
                    $ctrl->output->okf("Spooling redirected to STDOUT");
                } else {
                    $ctrl->output->okf("Spooling redirected to %s", quote($args));
                }
            } else {
                $ctrl->output->infof("Spool is set to %s", quote(''));
            }
        },
    );
}

1;
