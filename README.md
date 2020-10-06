# Hugo/S3 Container + Utilities

This git repository includes:
1. Bash scripts to automate the setup of your S3 buckets & TLS enabled Cloudfront distribution (if you don't already have one setup) -- all you need is a domain name from [Route53](https://aws.amazon.com/route53/)
    * If you want your website to be TLS enabled, you need to configure a Cloudfront distrubitution, so these are actually pretty helpful; if you don't know what you're doing it can get kinda thorny. If you'd rather do it manually, read [this article](https://itnext.io/hugo-website-with-ssl-on-s3-is-straightforward-right-errrrm-369c0f19ab07?gi=16d0cccb8a88)
2.`Dockerfile` to build the image hosted here, see next section for more info (pre-build image available via `docker pull l0xy/hugo-s3-docker`)
3. a `Makefile` that will allow you to, among other things, painlessly test and edit your website via Docker by simply typing `make`
    * `make deploy` --  deploy your Hugo site to S3 per your Hugo sites `config.toml` file after making and testing changes

## `Makefile` workflow

When using the `Makefile`, the source code for the Hugo project you want to work with in a directory named `src/` located in the same directory as the `Makefile` 

If you have multiple Hugo sites you would like to use with this workflow, it's easiest to clone this repo and link the `Makefile` into the parent directory ofeach projects source, e.g.:

```
git clone https://github.com/l0xy/hugo-s3.git
ln -s hugo-s3/Makefile site1.com/
ln -s hugo-s3/Makefile site2.com/
```

where the directories `site1.com/` and `site2.com/` have the structure:
```
./site1.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───config/
    ├───content/
    ├───layouts/
    └───static/ 

./site2.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───config/
    ├───content/
    ├───layouts/
    └───static/ 
```

This way you can just `cd` to the directory named after the site you're attempting to work on and run `make` to serve the site locally.

### `Makefile` targets

#### `make image`

Generates a Docker image named `hugo-s3` that contains everything you need to generate the Hugo site you've got the source for on your local machine.

This image is also available via `docker pull l0xy/hugo-s3`, however this `make` target is available for those wish to modify the Docker container.

#### `make serve`

Since this is the default target, you can serve the site locally simply by running `make`. This allows live editing so you can test the site as you're editing/testing/creating it; the site is accessible from `http://localhost:1313` in your browser.

#### `make deploy`

This just generates and deploys the site to the first deployment listed in your hugo configuration. 
```
    [deployment]
      [[deployment.targets]]
      name = "S3 hosted Hugo site"
      URL = "s3://<Bucket Name>?region=<AWS region>"
      cloudFrontDistributionID = <ID>
```

Before running `make deploy` it is assumed that you have:
 - an s3 bucket configured properly (publicly accessible, configured to host a static site, etc), see [here](https://capgemini.github.io/development/Using-S3-and-Hugo-to-Create-Hosting-Static-Website/). This can be done using the shell script that comes with the repository :)
 - a file `~/.aws/credentials` containing the credentials needed to access said bucket, i.e. you have configured the aws-cli on your local machine. The simplest way to do that is just to configure the AWS CLI on your machine, however it's not required as `aws-cli` is run from the Docker container. 

## Docker image

If you're not interested in downloading the workflow tools in the git repository above and you just want to start using this Docker you built via the Dockerfile or downloaded via `docker pull l0xy/hugo-s3`, here's what you need to know:
 
This docker image is configured with 3 main tools: 
  1. [Hugo extended](https://gohugo.io/getting-started/installing/) - pretty much the same as regular Hugo, but includes support for [Sass/SCSS](https://sass-lang.com/)
  2. [asciidoctor](https://asciidoctor.org/) - provides the option of writing your Hugo site in a much richer markup language than traditional Markdown
  3. [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install) - for S3 deployment

Additionally these ruby gems have been installed for use with asciidoctor:

- `asciidoctor-rouge`
- `asciidoctor-interdoc-reftext`
- `asciidoctor-diagram asciidoctor-html5s`

If you want to use Hugo with Markdown instead of asciidoctor that's fine, the other softwares won't get in your way or prevent you from doing so.

