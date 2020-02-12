#!/usr/bin/env zsh

hugo
find . \! -newermt '100 years ago' -exec touch {} \;
#touch public
#find public/js -type d -exec touch {} \;
#find public/img -type d -exec touch {} \;
