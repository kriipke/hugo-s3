#!/bin/sh

if [ $DEPLOY ]; then
    cp -r /src/* /output/ && cd /output/
    hugo --gc --minify
    hugo deploy
else
    hugo server --bind '0.0.0.0' -D
fi
