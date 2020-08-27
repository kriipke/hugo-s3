# Hugo/s3 workflow container

This repository contains two things, really:
 - the Dockerfile to generate a Docker image containing Hugo & asciidoctor that will allow you to generate a static website using the Hugo source on your local machine
 - a Makefile containing the primary functions needed during the workflow of editing, testing, and deploying your Hugo site to an AWS s3 bucket for hosting

## make image

Generates a Docker image named `hugo-s3` that contains everything you need to generate the Hugo site you've got the source for on your local machine

## make serve

Generates and serves the site provided in `./src` locally on your machinewith live updating so you can test the site as your working on it. The site is accessible from `http://localhost:1313` in your browser.

If you want to serve a Hugo site located somewhere other than the `src` dir located in the root of this directory you can pass the path tohe site via the `SRC_DIR` variable to make as such:

`make SRC_DIR=/path/to/hugo/site serve`

## make deploy

This just generates and deploys the site to the first deployment listed in your hugo configuration. Note that `make deploy` assumes you have:
 - an s3 bucket configured properly (publicly accessible, configured to host a static site, etc), see [here](https://capgemini.github.io/development/Using-S3-and-Hugo-to-Create-Hosting-Static-Website/)
 - a file `~/.aws/credentials` containing the credentials needed to access said bucket, i.e. you have configured the aws-cli on your local machine

Like `make serve`, you may specify an alternate path to the Hugo site on your machine you wish to deploy:

`make SRC_DIR=/path/to/hugo/site deploy`
