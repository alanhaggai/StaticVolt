package StaticVolt::Convertor;

use strict;
use warnings;

my %convertor;

sub has_convertor {
    my ( $self, $extension ) = @_;

    if ( exists $convertor{$extension} ) {
        return 1;
    }
    return;
}

sub convert {
    my ( $self, $content, $extension ) = @_;

    no strict 'refs';
    return &{"${convertor{$extension}}::convert"}($content);
}

sub register {
    my ( $class, @extensions ) = @_;

    for my $extension (@extensions) {
        $convertor{$extension} = $class;
    }
}

1;
