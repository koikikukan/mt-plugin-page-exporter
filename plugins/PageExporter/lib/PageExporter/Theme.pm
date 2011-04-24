package PageExporter::Theme;
use strict;

use MT;
use MT::Page;

sub condition {
    my ( $blog ) = @_;

    my $page = MT->model('page')->load({ blog_id => $blog->id }, { limit => 1 });
    return defined $page ? 1 : 0;
}

sub template {
    my $app = shift;
    my ( $blog, $saved ) = @_;

    my @pages = MT->model('page')->load({
        blog_id => $blog->id,
    });
    return unless scalar @pages;
    my @list;
    my %checked_ids;
    if ( $saved ) {
        %checked_ids = map { $_ => 1 } @{ $saved->{plugin_default_pages_export_ids} };
    }
    for my $page ( @pages ) {
        push @list, {
            page_title  => $page->title,
            page_id     => $page->id,
            checked      => $saved ? $checked_ids{ $page->id } : 1,
        };
    }
    my %param = ( pages => \@list );

    my $template_file;
    if (MT->version_number < 5.1) {
        $template_file = 'export_page_50.tmpl';
    } else {
        $template_file = 'export_page.tmpl';
    }
    my $plugin = MT->component('PageExporter');
    return $plugin->load_tmpl($template_file, \%param);
}

sub export {
    my ( $app, $blog, $settings ) = @_;
    my @pages;
    if ( defined $settings ) {
        my @ids = $settings->{plugin_default_pages_export_ids};
        @pages = MT->model('page')->load({ id => \@ids });
    }
    else {
        @pages = MT->model('page')->load({ blog_id => $blog->id });
    }
    return unless scalar @pages;

    my $data = {};
    for my $page ( @pages ) {
        my $folder = $page->folder;
        my $path = $folder->basename if $folder;
        do {
            $folder = $folder && $folder->parent ?
                MT->model('folder')->load($folder->parent) : undef;
            $path = join "/", $folder->basename, $path if $folder;
        } while ($folder);
        my $hash = {
            title => $page->title,
            text => $page->text,
            text_more => $page->text_more,
            excerpt => $page->excerpt,
            keywords => $page->keywords,
            convert_breaks => $page->convert_breaks,
            status => $page->status,
            authored_on => $page->authored_on,
            created_on => $page->created_on,
            modified_on => $page->modified_on,
            allow_comments => $page->allow_comments,
            allow_pings => $page->allow_pings,
            basename => $page->basename,
            tags  => join(',', $page->get_tags),
            folder  => $path,
        };
        $data->{ $page->id } = $hash;
    }
    return %$data ? $data : undef;
}

sub import {
    my ( $element, $theme, $obj_to_apply ) = @_;
    my $entries = $element->{data};
    _add_entries( $theme, $obj_to_apply, $entries, 'page' )
        or die "Failed to create theme default Pages";
    return 1;
}

sub _add_entries {
    my ( $theme, $blog, $pages, $class ) = @_;
    my $app = MT->instance;
    my @text_fields = qw(
        title   text     text_more
        excerpt keywords
    );
    PAGE: for my $id ( keys %$pages ) {
        my $page = $pages->{$id};
        my $iter = MT->model($class)->load_iter({
            basename => $page->{basename},
            blog_id  => $blog->id,
        });

        # check same basename
        while (my $p = $iter->()) {
            my $folder = $p->folder;
            my $path = $folder->basename if $folder;
            do {
                $folder = $folder && $folder->parent ?
                    MT->model('folder')->load($folder->parent) : undef;
                $path = join "/", $folder->basename, $path if $folder;
            } while ($folder);
            next PAGE if $path eq $page->{folder};
        }

        next if MT->model($class)->count({
            title => $page->{title},
            blog_id  => $blog->id,
        });
        my $obj = MT->model($class)->new();
        my $current_lang = MT->current_language;
        MT->set_language($blog->language);
        $obj->set_values({
            map { $_ => $theme->translate_templatized( $page->{$_} ) }
            grep { exists $page->{$_} }
            @text_fields
        });
        MT->set_language( $current_lang );

        $obj->basename( $page->{basename} );
        $obj->blog_id( $blog->id );
        $obj->author_id( $app->user->id );

        $obj->convert_breaks( $page->{convert_breaks} );
        $obj->authored_on( $page->{authored_on} );
        $obj->created_on( $page->{created_on} );
        $obj->modified_on( $page->{modified_on} );
        $obj->allow_comments( $page->{allow_comments} );
        $obj->allow_pings( $page->{allow_pings} );
        $obj->status(
            exists $page->{status} ? $page->{status} : MT::Entry::RELEASE()
        );
        if ( my $tags = $page->{tags} ) {
            my @tags = ref $tags ? @$tags : split( /\s*\,\s*/, $tags );
            $obj->set_tags( @tags );
        }

        $obj->save or die $obj->errstr;

        my $path_str;
        if ( $class eq 'page' && ($path_str = $page->{folder}) ) {
            my @paths = split( '/', $path_str );
            my ($current, $parent);
            PATH: while ( my $path = shift @paths ) {
                my $terms = {
                    blog_id  => $blog->id,
                    basename => $path,
                };
                $terms->{parent} = $parent->id if $parent;
                $current = MT->model('folder')->load($terms);
                if ( !$current ) {
                    unshift @paths, $path;
                    while ( my $new = shift @paths ) {
                        my $f = MT->model('folder')->new();
                        $f->set_values({
                            blog_id   => $blog->id,
                            author_id => $app->user->id,
                            label     => $new,
                            basename  => $new,
                        });
                        $f->parent( $parent->id ) if $parent;
                        $f->save;
                        $parent = $f;
                    }
                    last PATH;
                }
                $parent = $current;
            }
            my $place = MT->model('placement')->new;
            $place->set_values({
                blog_id     => $blog->id,
                entry_id    => $obj->id,
                category_id => $parent->id,
                is_primary  => 1,
            });
            $place->save;
        }
    }
    1;
}

sub info {
    my ( $element, $theme, $blog ) = @_;
    my $data = $element->{data};

    return sub {
        MT->translate( 'Pages' ) .'('. MT->translate( '[_1] pages', scalar keys %{$element->{data}} ) .')';
    };
}

1;
