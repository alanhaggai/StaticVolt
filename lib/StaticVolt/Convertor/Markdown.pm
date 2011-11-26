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
