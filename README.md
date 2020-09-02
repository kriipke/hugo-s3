# Hugo/S3 Container + Utilities

This git repository includes:
1. Bash scripts to automate the setup of your S3 buckets & TLS enabled Cloudfront distribution (if you don't already have one setup) -- all you need is a domain name from [Route53](https://aws.amazon.com/route53/)
    * If you want your website to be TLS enabled, you need to configure a Cloudfront distrubitution, so these are actually pretty helpful; if you don't know what you're doing it can get kinda thorny. If you'd rather do it manually, read [this article](https://itnext.io/hugo-website-with-ssl-on-s3-is-straightforward-right-errrrm-369c0f19ab07?gi=16d0cccb8a88)
2.`Dockerfile` to build the image hosted here, see next section for more info (pre-build image available via `docker pull l0xy/hugo-s3-docker`)
3. a `Makefile` that will allow you to easily use this Docker container via the following commands:
    * `make serve`--  test your Hugo website locally @ `http://localhost:1313`
    * `make deploy` --  deploy your Hugo site to S3 per your Hugo sites `config.toml` file after making and testing changes

## `Makefile` workflow

When using the `Makefile`, the source code for the Hugo project you want to work with can either be located:
1. in a directory named `src/` located in the same directory as the `Makefile` 
2. in the directory explicitly passed to `make` via the `SRC_DIR` variable, e.g.:
  * `make SRC_DIR=/path/to/hugo/site serve`
  * `make SRC_DIR=/path/to/hugo/site deploy`

If you have multiple Hugo sites you would like to use with this workflow, rather than explicitly pass in the path to the Hugo site each time as described above I would recommend linking the `Makefile` into a directory both:
1. named after the site
2. containing a directory named `src/` with the contents of the Hugo project.

For example:
```
./site1.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───content/
    ├───themes/
    └───layouts/

./site2.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───content/
    ├───themes/
    └───layouts/ 
```

This way you can just `cd` to the directory named after the site you're trying to work with and `make serve` or `make deploy` will work as expected.

### `make image`

Generates a Docker image named `hugo-s3` that contains everything you need to generate the Hugo site you've got the source for on your local machine

This image is also available via `docker pull l0xy/hugo-s3`

### `make serve`

Generates and serves your Hugo project locally on your machine with live updating so you can test the site as you're editing/testing it; the site is accessible from `http://localhost:1313` in your browser.

### `make deploy`

This just generates and deploys the site to the first deployment listed in your hugo configuration. Note that `make deploy` assumes you have:
 - an s3 bucket configured properly (publicly accessible, configured to host a static site, etc), see [here](https://capgemini.github.io/development/Using-S3-and-Hugo-to-Create-Hosting-Static-Website/)
 - a file `~/.aws/credentials` containing the credentials needed to access said bucket, i.e. you have configured the aws-cli on your local machine

## Docker image

If you're not interested in downloading the workflow tools in the git repository above and you just want to start using this Docker you built via the Dockerfile or downloaded via `docker pull l0xy/hugo-s3`, here's what you need to know:
 
This docker image is configured with 3 pieces of software:
  1. [Hugo extended](https://gohugo.io/getting-started/installing/) - pretty much the same as regular Hugo, but includes support for [Sass/SCSS](https://sass-lang.com/)
  2. [asciidoctor](https://asciidoctor.org/) - provides the option of writing your Hugo site in a much richer markup language than traditional Markdown
  3. [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install) - for S3 deployment

If you only need Hugo that's fine, the other softwares won't get in your way.

 ### A. serve/test the site locally
    -  run `docker run -it --rm -v $PATH_TO_HUGO_PROJECT:/src -p 1313:1313 l0xy/hugo-s3`
    - navigate to `http://localhost:1313` in your browser
 
### B. deploy the site to AWS S3
  1. configure a deployment in your Hugo projects configuration file, for a simple S3 deployment your deployment section in your `config.toml` will look something like
```
    [deployment]
    [[deployment.targets]]
    name = "S3 hosted Hugo site"
    URL = "s3://<Bucket Name>?region=<AWS region>"
    cloudFrontDistributionID = <ID>
```
  2. configure AWS CLI on your local machine (all that matters is that you have the file `~/.aws/credentials` in your home folder, the easiest way to do that is just to configure the AWS CLI on your machine)
  3. run `docker run --rm -e "DEPLOY=1" -v $HOME/.aws:/root/.aws -v $PATH_TO_HUGO_PROJECT:/src l0xy/hugo-s3`
