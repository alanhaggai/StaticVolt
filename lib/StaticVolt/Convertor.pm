# ABSTRACT: Base class for StaticVolt convertors

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

__END__

=method C<has_convertor>

Accepts a filename extension and returns a boolean result which indicates
whether the particular extension has a registered convertor or not.

=method C<convert>

Accepts content and filename extension as the parametres. Returns HTML after
converting the content using the convertor registered for that extension.

=func C<register>

Accepts a list of filename extensions and registers a convertor for each
extension.
