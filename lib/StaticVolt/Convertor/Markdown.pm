package StaticVolt::Convertor::Markdown;

use strict;
use warnings;

use base qw( StaticVolt::Convertor );

use Text::Markdown qw( markdown );

sub convert {
    my $content = shift;
    return markdown $content;
}

__PACKAGE__->register(qw/ markdown md mkd /);

1;

__END__

=head1 Registered Extensions

=over 4

=item * C<markdown>

=item * C<md>

=item * C<mkd>

=back
