#!/usr/bin/env bash

prepare_installer_copy() {
    local source_root=$1
    local output=$2
    local file="" name="" digest=""

    cp "$source_root/install.sh" "$output"
    for pair in \
        "statusline.sh:STATUSLINE_SHA256" \
        "lib/statusline_themes.sh:THEMES_LIB_SHA256" \
        "lib/statusline_display.sh:DISPLAY_LIB_SHA256" \
        "lib/statusline_usage.sh:USAGE_LIB_SHA256"; do
        file=${pair%%:*}
        name=${pair##*:}
        digest=$(perl -MDigest::SHA=sha256_hex -e '
            open my $fh, "<", shift or die $!;
            binmode $fh;
            my $sha = Digest::SHA->new(256);
            $sha->addfile($fh);
            print $sha->hexdigest;
        ' "$source_root/$file")
        INSTALL_DIGEST="$digest" INSTALL_NAME="$name" perl -pi -e '
            my $name = $ENV{INSTALL_NAME};
            my $digest = $ENV{INSTALL_DIGEST};
            s/^\Q$name\E="[^"]*"/$name="$digest"/;
        ' "$output"
    done
}
