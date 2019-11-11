#!/bin/bash

#initial setup
rm -rf dist
rm shifting-sands.love
rm shifting-sands-win.zip

#libraries used; minimal rather than including all their repo fluff
partner="lib/partner/partner.lua lib/partner/license.txt"
libs="$partner"

#raw love2d file
cd ..
zip -r pack/shifting-sands.love *.lua src assets $libs config
cd pack


#windows
mkdir dist
cat ./win/love.exe shifting-sands.love > dist/shifting-sands.exe
cp ./win/*.dll dist
cp ./win/license.txt dist/license_love2d.txt
cd dist
zip -r ../shifting-sands-win.zip .
cd ..
rm -rf dist
